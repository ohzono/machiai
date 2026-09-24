import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle("Capture prompts", isOn: $preferences.isCaptureEnabled)
                Toggle("Translate only while Machiai is open", isOn: $preferences.translatesOnlyWhileOpen)
                TextField("Model", text: $preferences.model, prompt: Text(Preferences.defaultModel))
                TextField(
                    "Translate into",
                    text: $preferences.targetLanguage,
                    prompt: Text(Preferences.defaultTargetLanguage)
                )
            } header: {
                Text("Translation")
            } footer: {
                Text("Each captured prompt costs one claude -p call on your own account. With \"only while open\", nothing is translated or spent while Machiai is closed. Set MACHIAI_TRANSLATE_CMD in config.env to use another translator.")
                    .foregroundStyle(.secondary)
            }

            Section("Reading") {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $preferences.readingFontSize, in: Preferences.fontSizeRange, step: 1)
                            .frame(width: 180)
                        Text("\(Int(preferences.readingFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Hide Machiai when everything is read", isOn: $preferences.hidesWhenInboxEmpty)
            }

            Section("Claude Code") {
                HookInstallSection()
                HStack {
                    Button("Show Files in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.home])
                    }
                    if model.installer.isInstalled {
                        Button("Uninstall Hook", role: .destructive) {
                            Task { await model.installer.uninstall() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.installer.refresh() }
    }
}
