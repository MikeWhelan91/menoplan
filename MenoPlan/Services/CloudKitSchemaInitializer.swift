#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Debug-only: creates every record type and field LineCheck syncs in the
/// iCloud *development* database, ready to deploy to production from the
/// CloudKit Console. Debug builds run with iCloud sync off, so without this
/// new models and fields never reach the development schema.
///
/// Uses a throwaway store in the temporary directory - the person's real
/// data isn't opened or uploaded.
enum CloudKitSchemaInitializer {
    enum Failure: LocalizedError {
        case modelUnavailable
        var errorDescription: String? { "Couldn't build the data model for iCloud." }
    }

    static func initialize() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: LineCheckApp.persistentModelTypes) else {
            throw Failure.modelUnavailable
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloudkit-schema-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: LineCheckApp.cloudKitContainerIdentifier)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "LineCheckSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema()

        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
