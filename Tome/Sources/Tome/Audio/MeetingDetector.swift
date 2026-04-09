import CoreAudio
import AppKit
import Observation

/// Monitors the system default input device's "is running" property to detect
/// when another app (e.g. Teams) starts using the microphone, then checks if
/// a known conferencing app is running.
@Observable
@MainActor
final class MeetingDetector {
    private(set) var detectedApp: (bundleID: String, name: String)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var stopDebounceTask: Task<Void, Never>?
    private var isInstalled = false

    /// How long to wait after the mic is released before signaling stop (seconds).
    private let stopDelay: UInt64 = 20

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

    var onMeetingStarted: ((String, String) -> Void)?  // (bundleID, appName)
    var onMeetingStopped: (() -> Void)?

    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleMicRunningChange()
            }
        }
        listenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Listen on default input device
        guard let deviceID = defaultInputDeviceID() else { return }
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)

        // Also listen for default device changes so we can re-attach
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceChangeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.reattachListener()
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            deviceChangeBlock
        )
    }

    func uninstall() {
        guard isInstalled, let block = listenerBlock else { return }
        isInstalled = false
        stopDebounceTask?.cancel()

        if let deviceID = defaultInputDeviceID() {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        listenerBlock = nil
    }

    // MARK: - Private

    private func handleMicRunningChange() {
        let micInUse = isMicRunning()
        diagLog("[MEETING-DETECT] mic running = \(micInUse)")

        if micInUse {
            stopDebounceTask?.cancel()
            stopDebounceTask = nil

            // Already tracking a meeting
            guard detectedApp == nil else { return }

            // Check if a conferencing app is running
            if let app = findRunningConferencingApp() {
                diagLog("[MEETING-DETECT] detected conferencing app: \(app.name) (\(app.bundleID))")
                detectedApp = app
                onMeetingStarted?(app.bundleID, app.name)
            }
        } else {
            // Mic released — debounce before signaling stop
            guard detectedApp != nil else { return }
            stopDebounceTask?.cancel()
            stopDebounceTask = Task {
                try? await Task.sleep(for: .seconds(stopDelay))
                guard !Task.isCancelled else { return }
                // Re-check: mic might have resumed (e.g. brief mute)
                if !self.isMicRunning() {
                    diagLog("[MEETING-DETECT] mic still off after delay, stopping session")
                    self.detectedApp = nil
                    self.onMeetingStopped?()
                }
            }
        }
    }

    private func findRunningConferencingApp() -> (bundleID: String, name: String)? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  let name = conferencingBundleIDs[bundleID] else { continue }
            return (bundleID, name)
        }
        return nil
    }

    private func isMicRunning() -> Bool {
        guard let deviceID = defaultInputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private func reattachListener() {
        guard isInstalled, let block = listenerBlock else { return }
        // Remove from old device (best-effort, may fail if device gone)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Re-attach to new default device
        if let deviceID = defaultInputDeviceID() {
            AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
            diagLog("[MEETING-DETECT] reattached listener to device \(deviceID)")
        }
    }
}
