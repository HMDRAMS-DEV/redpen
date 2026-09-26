import Foundation
import OSLog
import Photos
import UniformTypeIdentifiers

/// Finds screenshots that reach this Mac through iCloud Photos, usually taken on an iPhone or iPad.
/// Each one is copied to the cache once, so the rest of Redpen treats it like any other file.
@MainActor
final class PhotosWatcher: NSObject, PHPhotoLibraryChangeObserver {
    /// Newest first.
    private(set) var captures: [ScreenshotWatcher.Capture] = []
    var onChange: (([ScreenshotWatcher.Capture]) -> Void)?

    private var started = false
    private var refreshing = false
    private var refreshAgain = false
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Redpen", category: "photos")

    nonisolated private static let folder = URL.cachesDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "Redpen")
        .appending(path: "iCloud Photos")

    /// Whether a screenshot came from another device, through this watcher.
    nonisolated static func contains(_ url: URL) -> Bool {
        url.path.hasPrefix(folder.path)
    }

    /// Does nothing until the person allows Photos access, so it never prompts on its own.
    func start() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard !started, status == .authorized || status == .limited else { return }
        started = true
        PHPhotoLibrary.shared().register(self)
        Self.log.info("Watching iCloud Photos for screenshots")
        refresh()
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.refresh() }
    }

    /// One refresh at a time. Photos reports changes constantly while iCloud syncs, and
    /// cancelling on each one would drop a screenshot that's still downloading.
    private func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        Task {
            defer {
                refreshing = false
                if refreshAgain {
                    refreshAgain = false
                    refresh()
                }
            }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate >= %@",
                                            PHAssetMediaSubtype.photoScreenshot.rawValue,
                                            Date.now.addingTimeInterval(-3 * 86400) as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 20
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var found: [ScreenshotWatcher.Capture] = []
            for asset in result.objects(at: IndexSet(integersIn: 0..<result.count)) {
                guard let date = asset.creationDate else { continue }
                guard let url = await Self.file(for: asset) else {
                    Self.log.error("Couldn't copy screenshot from \(date, privacy: .public)")
                    continue
                }
                found.append(ScreenshotWatcher.Capture(url: url, date: date))
            }
            guard found != captures else { return }
            Self.log.info("Found \(found.count) screenshots, newest from \(found.first?.date.description ?? "none", privacy: .public)")
            captures = found
            onChange?(found)
        }
    }

    /// The cached copy, downloading the original from iCloud the first time.
    private static func file(for asset: PHAsset) async -> URL? {
        let folder = folder.appending(path: asset.localIdentifier.replacingOccurrences(of: "/", with: "-"))
        if let cached = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first {
            return cached
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        let image: (data: Data, type: String?)? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, type, _, _ in
                continuation.resume(returning: data.map { ($0, type) })
            }
        }
        guard let image else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let date = formatter.string(from: asset.creationDate ?? .now)
        let ext = image.type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "png"
        let url = folder.appending(path: "Screenshot \(date).\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
