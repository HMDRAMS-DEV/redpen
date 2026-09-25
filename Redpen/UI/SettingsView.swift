import SwiftUI

struct SettingsView: View {
    @Environment(ReviewStore.self) private var store
    @AppStorage(Keys.askOnScreenshot) private var askOnScreenshot = true

    var body: some View {
        @Bindable var voice = store.voice
        @Bindable var updater = Updater.shared
        Form {
            Section {
                Picker("Voice", selection: $voice.engine) {
                    ForEach(VoiceEngine.allCases) { engine in
                        Text(engine.title)
                            .tag(engine)
                            .disabled(engine == .superwhisper && !voice.superwhisperInstalled)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(detail(voice.engine))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !voice.superwhisperInstalled {
                    Link("Get Superwhisper", destination: Voice.superwhisperSite)
                        .font(.system(size: 12, weight: .medium))
                }
            } header: {
                Text("After you circle something")
            }

            Section {
                Toggle("Ask to mark up new screenshots", isOn: $askOnScreenshot)
                Text("When you take screenshots, Redpen puts a red dot in the menu bar and sends one notification after the burst.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Screenshots")
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                LabeledContent("Version \(updater.version)") {
                    Button("Check Now") { updater.check() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ engine: VoiceEngine) -> String {
        switch engine {
        case .superwhisper:
            "Redpen starts Superwhisper when you circle or click. Stop it with your Superwhisper shortcut, and the transcript lands in the note."
        case .dictation:
            "Apple's speech recognition, on this Mac. It stops when you pause."
        case .typing:
            "No listening. Circle or click, then type."
        }
    }
}
