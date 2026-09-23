import SwiftUI

/// First-run screen: explains the idea and installs the Claude Code hook.
struct OnboardingView: View {
    var body: some View {
        // A ScrollView keeps the window's minimum height small: wrapped text measured at a narrow
        // proposed width would otherwise demand a very tall window.
        ScrollView {
            content
                .frame(maxWidth: 560, alignment: .leading)
                .padding(48)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "character.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)

            Text("Learn English while your agent thinks")
                .font(.largeTitle.weight(.semibold))

            Text("Machiai translates each prompt you type to Claude Code into natural English, in the background. Switch here with ⌘Tab, read how you would have said it, check it off, and go back to work.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HookInstallSection()
        }
    }
}

/// Install status, the install button and a copyable command. Shared by onboarding and Settings.
struct HookInstallSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let installer = model.installer
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        await installer.install()
                        model.preferences.reloadCaptureState()
                    }
                } label: {
                    Text((installer.isInstalled ? "Reinstall Hook" : "Install for Claude Code") as LocalizedStringKey)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(installer.isRunning)

                if installer.isRunning {
                    ProgressView().controlSize(.small)
                } else if installer.isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text("Adds one UserPromptSubmit hook to ~/.claude/settings.json (a backup is kept). New Claude Code sessions pick it up. Or run this in a terminal:")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(installer.installCommand)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            if !installer.lastOutput.isEmpty {
                Text(installer.lastOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
