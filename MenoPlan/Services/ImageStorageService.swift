import UIKit

/// Where a scan's picture can be found: the local-disk filename, and the bytes
/// mirrored through iCloud. Either half can be missing — a scan captured here
/// has a file before its blob is written, and a scan synced in from another
/// device has only the blob until this device materialises the file.
struct StoredImageRef: Sendable {
    var filename: String?
    var data: Data?

    var isEmpty: Bool { (filename?.isEmpty ?? true) && data == nil }

    static let none = StoredImageRef(filename: nil, data: nil)
}

final class ImageStorageService: Sendable {
    static let shared = ImageStorageService()
    private let directory: URL

    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "LineCheckImages")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes the local file and hands back the same bytes for the model's
    /// iCloud-mirrored attribute, so the two halves can never drift apart.
    func saveSyncable(_ image: UIImage, prefix: String = "scan", compression: CGFloat = 0.82) throws -> (filename: String, data: Data) {
        let filename = "\(prefix)-\(UUID().uuidString).jpg"
        let url = directory.appending(path: filename)
        let resized = ImageHelpers.resized(image, maxDimension: 1600)
        guard let data = resized.jpegData(compressionQuality: compression) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        return (filename, data)
    }

    func saveSyncableThumbnail(_ image: UIImage) throws -> (filename: String, data: Data) {
        try saveSyncable(ImageHelpers.resized(image, maxDimension: 260), prefix: "thumb", compression: 0.72)
    }

    func load(filename: String?) -> UIImage? {
        guard let filename, filename.isEmpty == false else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: filename).path)
    }

    /// Prefers the local file, falling back to the synced bytes and caching
    /// them to disk so later reads in this session hit the fast path.
    func load(_ ref: StoredImageRef) -> UIImage? {
        if let image = load(filename: ref.filename) { return image }
        guard let data = ref.data else { return nil }
        if let filename = ref.filename, filename.isEmpty == false {
            try? data.write(to: directory.appending(path: filename), options: .atomic)
        }
        return UIImage(data: data)
    }

    /// Bytes already on disk for `filename`, used to backfill scans saved
    /// before images were mirrored to iCloud.
    func fileData(filename: String?) -> Data? {
        guard let filename, filename.isEmpty == false else { return nil }
        return try? Data(contentsOf: directory.appending(path: filename))
    }

    /// Files currently cached on disk, with how recently each was written.
    /// The date lets a sweep leave a capture that is still mid-save alone.
    func cachedFiles() -> [(filename: String, modified: Date)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.map { url in
            let modified = (try? url.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast
            return (url.lastPathComponent, modified)
        }
    }

    func delete(filename: String?) {
        guard let filename, filename.isEmpty == false else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }
}
