import Foundation

/// Watches the inbox directory and triggers a scan when files appear or change.
///
/// Uses a kqueue-backed dispatch source on the directory (fires on create/rename/delete) with a
/// short debounce, plus a periodic rescan as a safety net. Never activates the app.
@MainActor
final class InboxWatcher {
    private let inboxURL: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingScan: DispatchWorkItem?

    init(inboxURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.inboxURL = inboxURL
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        onChange()

        let fd = open(inboxURL.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleScan() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
        pendingScan?.cancel()
        pendingScan = nil
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }
}
