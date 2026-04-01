import SwiftUI

struct SpeakerNamingView: View {
    /// Generic labels discovered by diarization, e.g. ["Speaker 2", "Speaker 3"]
    let speakerLabels: [String]
    /// Called with mapping from generic label -> user-entered name (empty values filtered out)
    let onApply: ([String: String]) -> Void
    /// Called when user wants to skip naming
    let onSkip: () -> Void

    @State private var names: [String: String] = [:]
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accent1)

                Text("Name Speakers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.fg1)

                Text("Assign names to the speakers\nidentified in this call.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.bottom, 20)

            // Speaker fields
            VStack(spacing: 8) {
                // "You" row — non-editable, shown for context
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.accent1.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("Y")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accent1)
                        )

                    Text("You")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.fg2)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Editable speaker rows
                ForEach(speakerLabels, id: \.self) { label in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.fg2.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(speakerInitial(label))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.fg2)
                            )

                        TextField(label, text: binding(for: label))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.fg1)
                            .focused($focusedField, equals: label)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.bg1.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(focusedField == label ? Color.accent1.opacity(0.4) : Color.white.opacity(0.06))
                            )
                            .onSubmit { advanceFocus(from: label) }
                    }
                    .padding(.horizontal, 12)
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Skip") { onSkip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    applyNames()
                } label: {
                    Text("Apply")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accent1, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg0)
        .onAppear {
            for label in speakerLabels {
                names[label] = ""
            }
            focusedField = speakerLabels.first
        }
    }

    private func binding(for label: String) -> Binding<String> {
        Binding(
            get: { names[label] ?? "" },
            set: { names[label] = $0 }
        )
    }

    private func speakerInitial(_ label: String) -> String {
        // "Speaker 2" -> "2", "Speaker 3" -> "3"
        String(label.last ?? "?")
    }

    private func applyNames() {
        let mapping = names
            .mapValues { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "") }
            .filter { !$0.value.isEmpty }
        onApply(mapping)
    }

    private func advanceFocus(from label: String) {
        guard let index = speakerLabels.firstIndex(of: label) else { return }
        let next = index + 1
        if next < speakerLabels.count {
            focusedField = speakerLabels[next]
        } else {
            applyNames()
        }
    }
}
