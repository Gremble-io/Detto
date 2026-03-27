import SwiftUI

struct PulsingDot: View {
    var size: CGFloat = 10
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ControlBar: View {
    let isRecording: Bool
    let activeSessionType: SessionType?
    let audioLevel: Float
    let detectedApp: String?
    let silenceSeconds: Int
    let statusMessage: String?
    let errorMessage: String?
    let onStartCallCapture: () -> Void
    let onStartVoiceMemo: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if let status = statusMessage, status != "Ready" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.accent1)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fg2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if isRecording {
                Button(action: onStop) {
                    HStack(spacing: 10) {
                        PulsingDot()

                        Text(activeSessionLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.fg1)

                        Spacer()

                        AudioLevelView(level: audioLevel)
                            .frame(width: 50, height: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if silenceSeconds >= 90 {
                    Text("Silence — auto-stop in \(120 - silenceSeconds)s")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            } else {
                HStack(spacing: 10) {
                    Button(action: onStartCallCapture) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accent1)
                            Text("Call Capture")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.fg2)
                            Text("⌘R")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.fg3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.bg1)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)

                    Button(action: onStartVoiceMemo) {
                        VStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accent1)
                            Text("Voice Memo")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.fg2)
                            Text("⌘⇧R")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.fg3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.bg1)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var activeSessionLabel: String {
        switch activeSessionType {
        case .callCapture:
            if let app = detectedApp {
                return "Recording — \(app)"
            }
            return "Recording Call"
        case .voiceMemo:
            return "Recording Memo"
        case nil:
            return "Recording"
        }
    }
}

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                let threshold = Float(i) / 6.0
                RoundedRectangle(cornerRadius: 1)
                    .fill(level > threshold ? Color.accent1.opacity(0.8) : Color.fg3.opacity(0.2))
                    .frame(width: 3)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
