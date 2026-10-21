import CoreData

@MainActor
protocol TripRepository {
    func load() throws -> [TripRecord]
    func save(_ trip: TripRecord) throws
}

/// A minimal Core Data schema for the initial practice-trip slice.
/// Extend with a versioned model and migration tests before adding real route data.
@MainActor
final class CoreDataTripRepository: TripRepository {
    private let container: NSPersistentContainer

    init() throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Trip"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let result = NSAttributeDescription()
            result.name = name
            result.attributeType = type
            result.isOptional = optional
            return result
        }
        entity.properties = [attribute("id", .UUIDAttributeType),
                             attribute("startedAt", .dateAttributeType),
                             attribute("endedAt", .dateAttributeType, optional: true),
                             attribute("status", .stringAttributeType)]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "Guardia", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        let directory = NSPersistentContainer.defaultDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        description.url = directory.appendingPathComponent("Guardia.sqlite")
        description.shouldAddStoreAsynchronously = false
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                              forKey: NSPersistentStoreFileProtectionKey)
        container.persistentStoreDescriptions = [description]
        var storeError: Error?
        container.loadPersistentStores { _, error in storeError = error }
        if let storeError { throw storeError }
    }

    func load() throws -> [TripRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return try container.viewContext.fetch(request).map { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let start = object.value(forKey: "startedAt") as? Date,
                  let raw = object.value(forKey: "status") as? String,
                  let status = TripStatus(rawValue: raw) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return TripRecord(id: id, startedAt: start,
                              endedAt: object.value(forKey: "endedAt") as? Date, status: status)
        }
    }

    func save(_ trip: TripRecord) throws {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "id == %@", trip.id as NSUUID)
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: "Trip", into: context)
        object.setValue(trip.id, forKey: "id")
        object.setValue(trip.startedAt, forKey: "startedAt")
        object.setValue(trip.endedAt, forKey: "endedAt")
        object.setValue(trip.status.rawValue, forKey: "status")
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
