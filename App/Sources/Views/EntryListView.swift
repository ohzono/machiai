import SwiftData
import SwiftUI

struct EntryListView: View {
    @Environment(AppModel.self) private var model
    @Query private var entries: [Entry]
    private let mailbox: Mailbox

    init(mailbox: Mailbox) {
        self.mailbox = mailbox
        let sort = [SortDescriptor(\Entry.createdAt, order: .reverse)]
        switch mailbox {
        case .unread:
            _entries = Query(filter: #Predicate<Entry> { !$0.isRead }, sort: sort)
        case .favorites:
            _entries = Query(filter: #Predicate<Entry> { $0.isFavorite }, sort: sort)
        case .all:
            _entries = Query(sort: sort)
        }
    }

    var body: some View {
        @Bindable var model = model
        List(entries, selection: $model.selectedEntryID) { entry in
            EntryRow(entry: entry)
                // NSTableView-backed Lists cache row heights; a new identity per status forces a
                // fresh measurement when the translation arrives.
                .id("\(entry.id)-\(entry.statusRaw)")
                .tag(entry.id)
                .contextMenu { EntryContextMenu(entry: entry) }
        }
        // Rows inserted into an NSTableView-backed List keep a stale height; rebuilding the list
        // when rows are added or removed measures them correctly.
        .id(entries.count)
        .overlay {
            if entries.isEmpty {
                emptyState
            }
        }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: entries.map(\.id)) { _, _ in selectFirstIfNeeded() }
    }

    /// Keeps something selected so ⌘↩ always has a target when there is anything to read.
    private func selectFirstIfNeeded() {
        if !entries.contains(where: { $0.id == model.selectedEntryID }) {
            model.selectedEntryID = entries.first?.id
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch mailbox {
        case .unread:
            ContentUnavailableView("No unread entries", systemImage: "tray")
        case .favorites:
            ContentUnavailableView(
                "No favorites yet",
                systemImage: "star",
                description: Text("Press ⌘D to keep a phrase worth remembering.")
            )
        case .all:
            ContentUnavailableView(
                "Nothing captured yet",
                systemImage: "text.bubble",
                description: Text("Type a prompt to your agent in your own language.")
            )
        }
    }
}

struct EntryRow: View {
    let entry: Entry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(entry.isRead ? Color.clear : Color.accentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
                .accessibilityLabel(entry.isRead ? Text("Read") : Text("Unread"))

            VStack(alignment: .leading, spacing: 3) {
                headline
                Text(entry.sourceText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 4) {
                    RelativeTimeText(date: entry.createdAt)
                    if let project = entry.projectName {
                        Text("·")
                        Text(project)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var headline: some View {
        switch entry.status {
        case .done:
            Text(entry.translation ?? "")
                .fontWeight(entry.isRead ? .regular : .semibold)
                .lineLimit(2, reservesSpace: true)
        case .pending:
            Text("Translating…")
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        case .failed:
            Label("Translation failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
    }
}

struct EntryContextMenu: View {
    @Environment(AppModel.self) private var model
    let entry: Entry

    var body: some View {
        if entry.isRead {
            Button("Mark as Unread") { model.markUnread(entry) }
        } else {
            Button("Mark as Read") { model.markRead(entry) }
        }
        Button((entry.isFavorite ? "Remove from Favorites" : "Add to Favorites") as LocalizedStringKey) {
            model.toggleFavorite(entry)
        }
        Button("Copy Translation") { model.copyTranslation(entry) }
            .disabled(entry.translation == nil)
        Divider()
        Button("Delete", role: .destructive) { model.delete(entry) }
    }
}
