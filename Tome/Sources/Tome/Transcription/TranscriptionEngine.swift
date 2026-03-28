import AVFoundation
import CoreAudio
import FluidAudio
import Observation
import os

// Writes to /tmp/tome.log
func diagLog(_ msg: String) {
    #if DEBUG
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/tome.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
    #endif
}

/// Dual-stream mic + system audio transcription.
@Observable
@MainActor
final class TranscriptionEngine {
    private(set) var isRunning = false
    var assetStatus: String = "Ready"
    var lastError: String?

    private let systemCapture = SystemAudioCapture()
    private let micCapture = MicCapture()
    private let transcriptStore: TranscriptStore

    /// Combined audio level from mic and system for the UI meter.
    var audioLevel: Float { max(micCapture.audioLevel, systemCapture.audioLevel) }

    private var micTask: Task<Void, Never>?
    private var sysTask: Task<Void, Never>?
    /// Keeps the mic stream alive for the audio level meter when transcription isn't running.
    private var micKeepAliveTask: Task<Void, Never>?

    /// Shared FluidAudio instances
    private var asrManager: AsrManager?
    private var vadManager: VadManager?

    /// Tracks the resolved mic device ID currently in use.
    private var currentMicDeviceID: AudioDeviceID = 0

    /// Tracks whether user selected "System Default" (0) or a specific device.
    private var userSelectedDeviceID: AudioDeviceID = 0

    /// Listens for default input device changes at the OS level.
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
    }

    func start(locale: Locale, inputDeviceID: AudioDeviceID = 0, appBundleID: String? = nil) async {
        diagLog("[ENGINE-0] start() called, isRunning=\(isRunning)")
        guard !isRunning else { return }
        lastError = nil

        guard await ensureMicrophonePermission() else { return }

        isRunning = true

        // 1. Load FluidAudio models
        assetStatus = "Downloading multilingual model (first run)..."
        diagLog("[ENGINE-1] loading FluidAudio ASR models...")
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            assetStatus = "Initializing ASR..."
            let asr = AsrManager(config: .default)
            try await asr.initialize(models: models)
            self.asrManager = asr

            assetStatus = "Loading VAD model..."
            diagLog("[ENGINE-1b] loading VAD model...")
            let vad = try await VadManager()
            self.vadManager = vad

            assetStatus = "Models ready"
            diagLog("[ENGINE-2] FluidAudio models loaded")
        } catch {
            let msg = "Failed to load models: \(error.localizedDescription)"
            diagLog("[ENGINE-2-FAIL] \(msg)")
            lastError = msg
            assetStatus = "Ready"
            isRunning = false
            return
        }

        guard let asrManager, let vadManager else { return }

        // 2. Start mic capture
        userSelectedDeviceID = inputDeviceID
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID()
        currentMicDeviceID = targetMicID ?? 0
        diagLog("[ENGINE-3] starting mic capture, targetMicID=\(String(describing: targetMicID))")
        let micStream = micCapture.bufferStream(deviceID: targetMicID)

        // 3. Start system audio capture
        diagLog("[ENGINE-4] starting system audio capture...")
        let sysStreams: SystemAudioCapture.CaptureStreams?
        do {
            sysStreams = try await systemCapture.bufferStream(appBundleID: appBundleID)
            diagLog("[ENGINE-5] system audio capture started OK")
        } catch {
            let msg = "Failed to start system audio: \(error.localizedDescription)"
            diagLog("[ENGINE-5-FAIL] \(msg)")
            lastError = msg
            sysStreams = nil
        }

        // 4. Start mic transcription
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrManager: asrManager,
            vadManager: vadManager,
            speaker: .you,
            audioSource: .microphone,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                }
            }
        )
        let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg }
        }
        micTask = Task.detached {
            let hadFatalError = await micTranscriber.run(stream: micStream)
            if hadFatalError {
                reportMicError("Mic transcription failed — restart session")
            }
        }

        // 5. Start system audio transcription
        if let sysStream = sysStreams?.systemAudio {
            let sysTranscriber = StreamingTranscriber(
                asrManager: asrManager,
                vadManager: vadManager,
                speaker: .them,
                audioSource: .system,
                onPartial: { text in
                    Task { @MainActor in store.volatileThemText = text }
                },
                onFinal: { text in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(text: text, speaker: .them))
                    }
                }
            )
            let reportSysError: @Sendable (String) -> Void = { [weak self] msg in
                Task { @MainActor in self?.lastError = msg }
            }
            sysTask = Task.detached {
                let hadFatalError = await sysTranscriber.run(stream: sysStream)
                if hadFatalError {
                    reportSysError("System audio transcription failed — restart session")
                }
            }
        }

        assetStatus = "Transcribing (Parakeet-TDT v3)"
        diagLog("[ENGINE-6] all transcription tasks started")

        // Install CoreAudio listener for default input device changes
        installDefaultDeviceListener()
    }

    /// Restart only the mic capture with a new device, keeping system audio and models intact.
    /// Pass the raw setting value (0 = system default, or a specific AudioDeviceID).
    func restartMic(inputDeviceID: AudioDeviceID) {
        guard isRunning, let asrManager, let vadManager else { return }

        // Only update user selection when explicitly changed (not from OS listener)
        if inputDeviceID != 0 || userSelectedDeviceID != 0 {
            userSelectedDeviceID = inputDeviceID
        }
        let targetMicID = inputDeviceID > 0 ? inputDeviceID : MicCapture.defaultInputDeviceID() ?? 0
        guard targetMicID != currentMicDeviceID else {
            diagLog("[ENGINE-MIC-SWAP] same device \(targetMicID), skipping")
            return
        }

        diagLog("[ENGINE-MIC-SWAP] switching mic from \(currentMicDeviceID) to \(targetMicID)")

        // Tear down old mic
        micTask?.cancel()
        micTask = nil
        micCapture.stop()

        currentMicDeviceID = targetMicID

        // Start new mic stream
        let micStream = micCapture.bufferStream(deviceID: targetMicID)
        let store = transcriptStore
        let micTranscriber = StreamingTranscriber(
            asrManager: asrManager,
            vadManager: vadManager,
            speaker: .you,
            audioSource: .microphone,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                }
            }
        )
        let reportMicError: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg }
        }
        micTask = Task.detached {
            let hadFatalError = await micTranscriber.run(stream: micStream)
            if hadFatalError {
                reportMicError("Mic transcription failed — restart session")
            }
        }

        diagLog("[ENGINE-MIC-SWAP] mic restarted on device \(targetMicID)")
    }

    // MARK: - Default Device Listener

    private func installDefaultDeviceListener() {
        guard defaultDeviceListenerBlock == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning, self.userSelectedDeviceID == 0 else { return }
                // User has "System Default" selected — follow the OS default
                self.restartMic(inputDeviceID: 0)
            }
        }
        defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        defaultDeviceListenerBlock = nil
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                assetStatus = "Ready"
            }
            return granted
        case .denied, .restricted:
            lastError = "Microphone access is disabled. Enable it in System Settings > Privacy & Security > Microphone."
            assetStatus = "Ready"
            return false
        @unknown default:
            lastError = "Unable to verify microphone permission."
            assetStatus = "Ready"
            return false
        }
    }

    func stop() async {
        lastError = nil
        removeDefaultDeviceListener()
        micTask?.cancel()
        sysTask?.cancel()
        micKeepAliveTask?.cancel()
        micTask = nil
        sysTask = nil
        micKeepAliveTask = nil
        await systemCapture.stop()
        micCapture.stop()
        currentMicDeviceID = 0
        isRunning = false
        assetStatus = "Ready"
    }

    /// Run offline diarization on the buffered system audio.
    /// Returns speaker segments (speakerId, startTime, endTime) or nil if no audio was buffered.
    nonisolated func runPostSessionDiarization() async -> [(speakerId: String, startTime: Float, endTime: Float)]? {
        guard let bufferURL = systemCapture.bufferFilePath,
              FileManager.default.fileExists(atPath: bufferURL.path) else {
            diagLog("[DIARIZE] No buffered system audio file found")
            return nil
        }

        diagLog("[DIARIZE] Starting post-session diarization on \(bufferURL.lastPathComponent)")

        do {
            let diarizer = OfflineDiarizerManager()

            diagLog("[DIARIZE] Preparing diarization models...")
            try await diarizer.prepareModels()

            diagLog("[DIARIZE] Processing audio...")
            let result = try await diarizer.process(bufferURL)

            let segments = result.segments.map { seg in
                (speakerId: seg.speakerId, startTime: seg.startTimeSeconds, endTime: seg.endTimeSeconds)
            }
            diagLog("[DIARIZE] Found \(segments.count) segments, \(Set(segments.map(\.speakerId)).count) speakers")

            systemCapture.cleanupBufferFile()
            return segments
        } catch {
            diagLog("[DIARIZE] Failed: \(error.localizedDescription)")
            systemCapture.cleanupBufferFile()
            return nil
        }
    }
}
