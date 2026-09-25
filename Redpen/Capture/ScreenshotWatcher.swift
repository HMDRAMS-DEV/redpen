import Foundation

/// Finds screenshots through Spotlight, which tags every capture with `kMDItemIsScreenCapture`.
/// That works wherever the screenshot folder is, with no folder watching and no polling.
@MainActor
final class ScreenshotWatcher: NSObject {
    struct Capture: Equatable, Identifiable {
        var url: URL
        var date: Date
        var id: URL { url }
    }

    /// Newest first.
    private(set) var captures: [Capture] = []
    var onChange: (([Capture]) -> Void)?

    private let query = NSMetadataQuery()

    func start() {
        guard !query.isStarted else { return }
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate >= %@",
                                      Date.now.addingTimeInterval(-3 * 86400) as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            center.addObserver(self, selector: #selector(update), name: name, object: query)
        }
        query.start()
    }

    func stop() {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func update() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let found = (0..<query.resultCount).compactMap { index -> Capture? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
            else { return nil }
            return Capture(url: URL(fileURLWithPath: path), date: date)
        }
        let fresh = found
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.date > $1.date }
        guard fresh != captures else { return }
        captures = fresh
        onChange?(fresh)
    }
}
