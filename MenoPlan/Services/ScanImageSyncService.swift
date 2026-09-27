import Foundation
import SwiftData

extension Scan {
    var originalImageRef: StoredImageRef { StoredImageRef(filename: imageFilename, data: imageData) }
    var enhancedImageRef: StoredImageRef { StoredImageRef(filename: enhancedImageFilename, data: enhancedImageData) }
    var autoEnhancedImageRef: StoredImageRef { StoredImageRef(filename: autoEnhancedImageFilename, data: autoEnhancedImageData) }
    var thumbnailImageRef: StoredImageRef { StoredImageRef(filename: thumbnailFilename, data: thumbnailData) }

    /// The picture to show at full size: whichever adjusted version exists,
    /// otherwise the original. Mirrors the fallback the views used when they
    /// chained filenames directly.
    var displayImageRef: StoredImageRef {
        Self.firstAvailable(enhancedImageRef, autoEnhancedImageRef, originalImageRef)
    }

    /// The same chain with the thumbnail ahead of the original, for grids and
    /// rows that only need a small picture.
    var compactImageRef: StoredImageRef {
        Self.firstAvailable(enhancedImageRef, autoEnhancedImageRef, thumbnailImageRef, originalImageRef)
    }

    /// A ref counts as present only if it can actually produce an image, so a
    /// filename left behind by a device that never uploaded its bytes falls
    /// through to the next candidate instead of dead-ending the chain.
    private static func firstAvailable(_ refs: StoredImageRef...) -> StoredImageRef {
        refs.first { $0.isEmpty == false } ?? .none
    }

    func clearAdjustedImages() {
        enhancedImageFilename = nil
        enhancedImageData = nil
        autoEnhancedImageFilename = nil
        autoEnhancedImageData = nil
    }
}

/// Keeps the local image cache and the iCloud-mirrored bytes in step at launch.
@ModelActor
actor ScanImageSyncService {
    private static let batchSize = 20
    /// A capture saves its file moments before the scan record exists, so the
    /// sweep ignores anything written recently rather than racing it.
    private static let orphanGracePeriod: TimeInterval = 300

    /// Copies images saved before iCloud mirroring existed out of the local
    /// Documents directory and into the model, where SwiftData's CloudKit
    /// exporter picks them up as assets. Idempotent: a scan whose bytes are
    /// already stored is filtered out in SQLite, so repeat launches cost one
    /// cheap fetch.
    func backfill() {
        let pending = pendingScans()
        guard pending.isEmpty == false else { return }

        let storage = ImageStorageService.shared
        for chunk in stride(from: 0, to: pending.count, by: Self.batchSize) {
            let slice = pending[chunk..<min(chunk + Self.batchSize, pending.count)]
            for scan in slice {
                if scan.imageData == nil { scan.imageData = storage.fileData(filename: scan.imageFilename) }
                if scan.thumbnailData == nil { scan.thumbnailData = storage.fileData(filename: scan.thumbnailFilename) }
                if scan.enhancedImageData == nil { scan.enhancedImageData = storage.fileData(filename: scan.enhancedImageFilename) }
                if scan.autoEnhancedImageData == nil { scan.autoEnhancedImageData = storage.fileData(filename: scan.autoEnhancedImageFilename) }
            }
            // Save per batch rather than once at the end so a large history is
            // handed to the CloudKit exporter in pieces instead of one
            // multi-hundred-megabyte transaction.
            try? modelContext.save()
        }
    }

    /// Scans still missing bytes for at least one of their images. Kept as four
    /// narrow fetches rather than one combined predicate: each runs in SQLite
    /// without loading any blobs, and the compiler type-checks them quickly.
    private func pendingScans() -> [Scan] {
        let predicates: [Predicate<Scan>] = [
            #Predicate<Scan> { $0.imageData == nil && $0.imageFilename != "" },
            #Predicate<Scan> { $0.thumbnailData == nil && $0.thumbnailFilename != nil },
            #Predicate<Scan> { $0.enhancedImageData == nil && $0.enhancedImageFilename != nil },
            #Predicate<Scan> { $0.autoEnhancedImageData == nil && $0.autoEnhancedImageFilename != nil }
        ]
        var seen: Set<PersistentIdentifier> = []
        var pending: [Scan] = []
        for predicate in predicates {
            guard let rows = try? modelContext.fetch(FetchDescriptor<Scan>(predicate: predicate)) else { continue }
            for scan in rows where seen.insert(scan.persistentModelID).inserted {
                pending.append(scan)
            }
        }
        return pending
    }

    /// Deleting a scan removes its record and its files on the device that did
    /// the deleting, but another device only learns about it through CloudKit -
    /// and by then it may have written its own cached copy of the picture.
    /// Nothing else would ever remove those, so sweep files no scan references.
    func pruneOrphanedFiles() {
        guard let scans = try? modelContext.fetch(FetchDescriptor<Scan>()) else { return }
        var referenced: Set<String> = []
        for scan in scans {
            referenced.insert(scan.imageFilename)
            if let name = scan.enhancedImageFilename { referenced.insert(name) }
            if let name = scan.autoEnhancedImageFilename { referenced.insert(name) }
            if let name = scan.thumbnailFilename { referenced.insert(name) }
        }

        let storage = ImageStorageService.shared
        let cutoff = Date.now.addingTimeInterval(-Self.orphanGracePeriod)
        for file in storage.cachedFiles() where referenced.contains(file.filename) == false && file.modified < cutoff {
            storage.delete(filename: file.filename)
        }
    }
}
