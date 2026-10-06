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
                        Text(engine.title).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(detail(voice.engine))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if voice.engine != .typing {
                    LabeledContent("Microphone") {
                        AccessButton(access: store.micAccess, allow: store.allowMicrophone)
                    }
                }
                if voice.engine == .parakeet {
                    Picker("Model", selection: $voice.model) {
                        ForEach(ParakeetModel.allCases) { model in
                            Text(model.name).tag(model)
                        }
                    }
                    Text(modelDetail(voice.model))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("After you circle something")
            }

            Section {
                Toggle("Ask to mark up new screenshots", isOn: $askOnScreenshot)
                Text("When you take screenshots, the menu bar loop turns red and circles how many are waiting. Redpen sends one notification after the burst.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Notifications") {
                    AccessButton(access: store.notificationAccess, allow: store.allowNotifications)
                }
                LabeledContent("iPhone and iPad screenshots") {
                    AccessButton(access: store.photosAccess, allow: store.allowPhotos)
                }
                Text("Screenshots from your other devices arrive through iCloud Photos. Redpen needs Photos access to find them.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Focus") {
                    Button("Open Focus Settings", action: store.openFocusSettings)
                }
                Text("A Focus hides notifications. To see Redpen's while one is on, add Redpen to that Focus's allowed apps.")
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
        case .parakeet:
            "A speech model on this Mac. Talk, and the note is written when you pause. Nothing leaves your Mac."
        case .dictation:
            "Apple's speech recognition, on this Mac. It stops when you pause."
        case .typing:
            "No listening. Circle or click, then type."
        }
    }

    private func modelDetail(_ model: ParakeetModel) -> String {
        let download = model.isDownloaded ? "Downloaded." : "Downloads the first time you talk."
        return "\(model.detail) \(download)"
    }
}
