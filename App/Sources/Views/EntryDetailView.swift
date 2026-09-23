import SwiftUI

/// The reading view: your words, then how you would say them.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    private var fontSize: Double { model.preferences.readingFontSize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: fontSize * 0.9) {
                metadata

                Text(entry.sourceText)
                    .font(.system(size: fontSize * 0.7))
                    .foregroundStyle(.secondary)
                    .lineSpacing(fontSize * 0.15)
                    .textSelection(.enabled)

                translation
                    .id(entry.status)
                    .transition(.opacity)

                actions
                    .padding(.top, 8)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .animation(.machiai, value: entry.status)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.toggleFavorite(entry)
                } label: {
                    Label(
                        (entry.isFavorite ? "Remove from Favorites" : "Add to Favorites") as LocalizedStringKey,
                        systemImage: entry.isFavorite ? "star.fill" : "star"
                    )
                }
                .help("Favorite (⌘D)")

                Button {
                    model.copyTranslation(entry)
                } label: {
                    Label("Copy Translation", systemImage: "doc.on.doc")
                }
                .disabled(entry.translation == nil)
                .help("Copy Translation (⇧⌘C)")
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if let project = entry.projectName {
                Label(project, systemImage: "folder")
                Text("·")
            }
            RelativeTimeText(date: entry.createdAt)
            if entry.isFavorite {
                Text("·")
                Label("Favorite", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.callout)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var translation: some View {
        switch entry.status {
        case .done:
            Text(entry.translation ?? "")
                .font(.system(size: fontSize))
                .lineSpacing(fontSize * 0.22)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .pending:
            TranslatingPlaceholder(sourceText: entry.sourceText, fontSize: fontSize, startedAt: entry.createdAt)
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Label("Translation failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: fontSize * 0.7, weight: .medium))
                if let message = entry.errorMessage {
                    Text(message)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        if entry.isRead {
            Button("Mark as Unread") { model.markUnread(entry) }
                .buttonStyle(.link)
        } else {
            Button {
                model.markRead(entry)
            } label: {
                Label("Mark as Read", systemImage: "checkmark")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Mark as Read (⌘↩)")
        }
    }
}

/// Shown while the translation is on its way: placeholder lines shaped like the source text,
/// gently breathing, and the elapsed seconds. Turns the wait into something to look at.
struct TranslatingPlaceholder: View {
    let sourceText: String
    let fontSize: Double
    let startedAt: Date
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceText)
                .font(.system(size: fontSize))
                .lineSpacing(fontSize * 0.22)
                .redacted(reason: .placeholder)
                .opacity(dimmed ? 0.35 : 0.8)
                .accessibilityHidden(true)

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Label {
                    Text("Translating… \(seconds)s")
                } icon: {
                    Image(systemName: "character.bubble")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: 1.1).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }
}
