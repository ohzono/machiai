import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } content: {
            EntryListView(mailbox: model.mailbox)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            DetailContainer()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                CaptureToggle()
            }
        }
        .onChange(of: model.mailbox) { _, _ in
            model.selectedEntryID = model.entries(in: model.mailbox).first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.installer.refresh()
            model.preferences.reloadCaptureState()
            model.importInbox()
            if model.selectedEntry == nil {
                model.selectedEntryID = model.entries(in: model.mailbox).first?.id
            }
        }
    }
}

private struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(Mailbox.allCases, selection: Binding(
            get: { model.mailbox },
            set: { if let value = $0 { model.mailbox = value } }
        )) { mailbox in
            Label {
                Text(mailbox.title)
            } icon: {
                Image(systemName: mailbox.systemImage)
            }
            .badge(mailbox == .unread ? model.unreadCount : 0)
            .tag(mailbox)
        }
        .navigationTitle("Machiai")
    }
}

private struct CaptureToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Toggle(isOn: $preferences.isCaptureEnabled) {
            Label(
                (preferences.isCaptureEnabled ? "Capturing" : "Paused") as LocalizedStringKey,
                systemImage: preferences.isCaptureEnabled ? "record.circle" : "pause.circle"
            )
        }
        .toggleStyle(.button)
        .help((preferences.isCaptureEnabled
              ? "Capturing new prompts. Click to pause."
              : "Paused. New prompts are not captured.") as LocalizedStringKey)
    }
}

private struct DetailContainer: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Entry> { !$0.isRead }) private var unread: [Entry]

    var body: some View {
        if let entry = model.selectedEntry {
            EntryDetailView(entry: entry)
                .id(entry.id)
        } else if !model.installer.isInstalled {
            OnboardingView()
        } else if unread.isEmpty {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("New translations appear here while your agent is thinking.")
            }
        } else {
            ContentUnavailableView("Select an entry", systemImage: "text.bubble")
        }
    }
}
