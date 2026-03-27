import SwiftUI
import AppKit
import Combine

private let conferencingBundleIDs: [String: String] = [
    "com.microsoft.teams2": "Teams",
    "com.microsoft.teams": "Teams",
    "us.zoom.xos": "Zoom",
    "com.apple.FaceTime": "FaceTime",
    "com.tinyspeck.slackmacgap": "Slack",
    "com.cisco.webexmeetingsapp": "Webex",
    "Cisco-Systems.Spark": "Webex",
    "com.google.Chrome": "Chrome",
    "company.thebrowser.Browser": "Arc",
    "com.apple.Safari": "Safari",
    "com.microsoft.edgemac": "Edge",
]

struct ContentView: View {
    @Bindable var settings: AppSettings
    @State private var transcriptStore = TranscriptStore()
    @State private var transcriptionEngine: TranscriptionEngine?
    @State private var sessionStore = SessionStore()
    @State private var transcriptLogger = TranscriptLogger()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var audioLevel: Float = 0
    @State private var activeSessionType: SessionType?
    @State private var detectedAppName: String?
    @State private var silenceSeconds: Int = 0
    @State private var savedFileURL: URL?
    @State private var bannerDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            topBar

            Divider()

            // Transcript view (primary content)
            TranscriptView(
                utterances: transcriptStore.utterances,
                volatileYouText: transcriptStore.volatileYouText,
                volatileThemText: transcriptStore.volatileThemText
            )

            Divider()

            if let url = savedFileURL, activeSessionType == nil {
                HStack {
                    Text("Saved to \(url.lastPathComponent)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fg2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        savedFileURL = nil
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accent1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Bottom bar: capture buttons + controls
            ControlBar(
                isRecording: isRunning,
                activeSessionType: activeSessionType,
                audioLevel: audioLevel,
                detectedApp: detectedAppName,
                silenceSeconds: silenceSeconds,
                statusMessage: transcriptionEngine?.assetStatus,
                errorMessage: transcriptionEngine?.lastError,
                onStartCallCapture: { startSession(type: .callCapture) },
                onStartVoiceMemo: { startSession(type: .voiceMemo) },
                onStop: stopSession
            )
        }
        .frame(minWidth: 280, maxWidth: 360, minHeight: 400)
        .background(Color.bg0)
        .preferredColorScheme(.dark)
        .overlay {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
                    .transition(.opacity)
            }
        }
        .onChange(of: showOnboarding) {
            if !showOnboarding {
                hasCompletedOnboarding = true
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
            if transcriptionEngine == nil {
                transcriptionEngine = TranscriptionEngine(transcriptStore: transcriptStore)
            }
        }
        // Audio level polling (replaces 0.1s Timer.publish)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let engine = transcriptionEngine else {
                    if audioLevel != 0 { audioLevel = 0 }
                    continue
                }
                if engine.isRunning {
                    audioLevel = engine.audioLevel
                    if audioLevel > 0.01 {
                        silenceSeconds = 0
                    }
                } else if audioLevel != 0 {
                    audioLevel = 0
                }
            }
        }
        // Silence auto-stop (replaces 1.0s Timer.publish)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning else {
                    silenceSeconds = 0
                    continue
                }
                if audioLevel < 0.01 {
                    silenceSeconds += 1
                    if silenceSeconds >= 120 {
                        stopSession()
                    }
                }
            }
        }
        // Transcript buffer flush
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await transcriptLogger.flushIfNeeded()
            }
        }
        .onChange(of: settings.inputDeviceID) {
            if isRunning {
                transcriptionEngine?.restartMic(inputDeviceID: settings.inputDeviceID)
            }
        }
        .onChange(of: transcriptStore.utterances.count) {
            handleNewUtterance()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("TOME")
                .font(.system(size: 20, weight: .bold))
                .tracking(8)
                .foregroundStyle(Color.fg1)

            Spacer()

            if isRunning {
                PulsingDot(size: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var isRunning: Bool {
        transcriptionEngine?.isRunning ?? false
    }

    // MARK: - Actions

    private func startSession(type: SessionType) {
        transcriptStore.clear()
        silenceSeconds = 0
        savedFileURL = nil
        bannerDismissTask?.cancel()

        // Determine output folder and app bundle ID based on session type
        let outputPath: String
        let sourceApp: String
        var appBundleID: String?
        var resolvedAppName: String?

        switch type {
        case .callCapture:
            outputPath = settings.vaultMeetingsPath
            // Detect frontmost conferencing app for per-app audio filtering
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier,
               let appName = conferencingBundleIDs[bundleID] {
                sourceApp = appName
                appBundleID = bundleID
                resolvedAppName = appName
            } else {
                sourceApp = "Call"
            }
        case .voiceMemo:
            outputPath = settings.vaultVoicePath
            sourceApp = "Voice Memo"
        }

        Task {
            transcriptionEngine?.lastError = nil
            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: sourceApp,
                    vaultPath: outputPath,
                    sessionType: type
                )
            } catch {
                await sessionStore.endSession()
                transcriptionEngine?.lastError = error.localizedDescription
                return
            }
            activeSessionType = type
            detectedAppName = resolvedAppName
            if type == .callCapture {
                await transcriptionEngine?.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID,
                    appBundleID: appBundleID
                )
            } else {
                // Voice memo — mic only, no system audio
                await transcriptionEngine?.start(
                    locale: settings.locale,
                    inputDeviceID: settings.inputDeviceID
                )
            }
        }
    }

    private func stopSession() {
        let wasCallCapture = activeSessionType == .callCapture
        activeSessionType = nil
        detectedAppName = nil
        silenceSeconds = 0

        Task {
            await transcriptionEngine?.stop()
            await sessionStore.endSession()
            await transcriptLogger.endSession()

            // Run post-session diarization only for call captures
            if wasCallCapture {
                transcriptionEngine?.assetStatus = "Identifying speakers..."
                if let segments = await transcriptionEngine?.runPostSessionDiarization() {
                    transcriptionEngine?.assetStatus = "Rewriting transcript..."
                    await transcriptLogger.rewriteWithDiarization(segments: segments)
                }
            }

            // Finalize frontmatter AFTER diarization (duration, speakers, rename)
            transcriptionEngine?.assetStatus = "Finalizing..."
            let savedPath = await transcriptLogger.finalizeFrontmatter()
            transcriptionEngine?.assetStatus = "Ready"

            // Only show banner if not already in a new session
            if activeSessionType == nil, let savedPath {
                savedFileURL = savedPath
                bannerDismissTask?.cancel()
                bannerDismissTask = Task {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { savedFileURL = nil }
                }
            }
        }
    }

    private func handleNewUtterance() {
        guard let last = transcriptStore.utterances.last else { return }

        // Reset silence timer on any speech
        silenceSeconds = 0

        // Persist to transcript log
        let speakerName = last.speaker == .you ? "You" : "Them"
        Task {
            await transcriptLogger.append(
                speaker: speakerName,
                text: last.text,
                timestamp: last.timestamp
            )
        }

        // Log session record
        Task {
            await sessionStore.appendRecord(SessionRecord(
                speaker: last.speaker,
                text: last.text,
                timestamp: last.timestamp
            ))
        }
    }
}
