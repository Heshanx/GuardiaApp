import CoreData

@MainActor
protocol TripRepository {
    func load() throws -> [TripRecord]
    func save(_ trip: TripRecord) throws
    func deleteFinished() throws
}


@MainActor
final class CoreDataTripRepository: TripRepository {
    private let container: NSPersistentContainer

    init(storeURL: URL? = nil) throws {
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
                             attribute("status", .stringAttributeType),
                             attribute("destination", .stringAttributeType, optional: true),
                             attribute("agreedFare", .doubleAttributeType, optional: true),
                             attribute("routePayload", .binaryDataAttributeType, optional: true),
                             attribute("paidFare", .doubleAttributeType, optional: true)]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "Guardia", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        let directory = NSPersistentContainer.defaultDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        description.url = storeURL ?? directory.appendingPathComponent("Guardia.sqlite")
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                              forKey: NSPersistentStoreFileProtectionKey)
        try Self.migrateOriginalStoreIfNeeded(at: description.url!, to: model)
        container.persistentStoreDescriptions = [description]
        var storeError: Error?
        container.loadPersistentStores { _, error in storeError = error }
        if let storeError { throw storeError }
    }


    private static func migrateOriginalStoreIfNeeded(at url: URL, to model: NSManagedObjectModel) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }
        let candidates: [NSManagedObjectModel] = [["paidFare"], ["paidFare", "routePayload"], ["paidFare", "routePayload", "destination", "agreedFare"]].map { removed in
            let candidate = model.copy() as! NSManagedObjectModel
            candidate.entities.first?.properties.removeAll { removed.contains($0.name) }
            return candidate
        }
        guard let original = candidates.first(where: { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }) else {
            throw CocoaError(.persistentStoreIncompatibleVersionHash)
        }
        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: original, destinationModel: model)
        let temporary = url.deletingLastPathComponent().appendingPathComponent("migration-\(UUID().uuidString).sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        defer {
            try? coordinator.destroyPersistentStore(at: temporary, ofType: NSSQLiteStoreType)
        }
        let manager = NSMigrationManager(sourceModel: original, destinationModel: model)
        try manager.migrateStore(from: url, sourceType: NSSQLiteStoreType, options: nil,
                                 with: mapping, toDestinationURL: temporary,
                                 destinationType: NSSQLiteStoreType, destinationOptions: nil)
        try coordinator.replacePersistentStore(at: url, destinationOptions: nil,
                                               withPersistentStoreFrom: temporary, sourceOptions: nil,
                                               ofType: NSSQLiteStoreType)
    }

    func deleteFinished() throws {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "status != %@", TripStatus.active.rawValue)
        do {
            for object in try context.fetch(request) { context.delete(object) }
            try context.save()
        } catch { context.rollback(); throw error }
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
            let route = try (object.value(forKey: "routePayload") as? Data).map { try JSONDecoder().decode(TripRoute.self, from: $0) }
            return TripRecord(id: id, startedAt: start,
                              endedAt: object.value(forKey: "endedAt") as? Date, status: status,
                              destination: object.value(forKey: "destination") as? String ?? "Practice trip",
                              agreedFare: object.value(forKey: "agreedFare") as? Double, paidFare: object.value(forKey: "paidFare") as? Double, route: route)
        }
    }

    func save(_ trip: TripRecord) throws {
        let routePayload = try trip.route.map { try JSONEncoder().encode($0) }
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "id == %@", trip.id as NSUUID)
        let object = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: "Trip", into: context)
        object.setValue(trip.id, forKey: "id")
        object.setValue(trip.startedAt, forKey: "startedAt")
        object.setValue(trip.endedAt, forKey: "endedAt")
        object.setValue(trip.status.rawValue, forKey: "status")
        object.setValue(trip.destination, forKey: "destination")
        object.setValue(trip.agreedFare, forKey: "agreedFare")
        object.setValue(trip.paidFare, forKey: "paidFare")
        object.setValue(routePayload, forKey: "routePayload")
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
