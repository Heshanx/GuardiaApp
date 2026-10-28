import Foundation
import CoreData
import Testing
@testable import GuardiaApp

@Suite("Local persistence")
@MainActor
struct GuardiaAppTests {
    private func temporaryStore() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("test.sqlite")
    }

    @Test("A finished trip survives reopening the store")
    func tripRoundTrip() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let start = Date(timeIntervalSince1970: 100)
        var trip = TripRecord(id: UUID(), startedAt: start, status: .active, destination: "Campus", agreedFare: 450)
        do {
            let repository = try CoreDataTripRepository(storeURL: url)
            try repository.save(trip)
            try trip.finish(as: .completed, at: start.addingTimeInterval(120))
            try repository.save(trip)
        }
        let restored = try CoreDataTripRepository(storeURL: url).load()
        #expect(restored.count == 1)
        #expect(restored.first?.destination == "Campus")
        #expect(restored.first?.agreedFare == 450)
        #expect(restored.first?.status == .completed)
        #expect(restored.first?.endedAt == start.addingTimeInterval(120))
    }

    @Test("Contacts persist and removal survives reopening")
    func contactRoundTrip() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let contact = TrustedContact(id: UUID(), name: "Amma", phone: "0772345678")
        do { try ContactRepository(storeURL: url).save(contact) }
        do {
            let repository = try ContactRepository(storeURL: url)
            #expect(try repository.load() == [contact])
            try repository.delete(contact)
        }
        #expect(try ContactRepository(storeURL: url).load().isEmpty)
    }
    @Test("Trips from the original programmatic schema migrate without data loss")
    func originalStoreMigration() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = UUID()
        do {
            let model = NSManagedObjectModel()
            let entity = NSEntityDescription()
            entity.name = "Trip"
            entity.managedObjectClassName = "NSManagedObject"
            entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("startedAt", .dateAttributeType),
                                 ("endedAt", .dateAttributeType), ("status", .stringAttributeType)].map { name, type in
                let attribute = NSAttributeDescription()
                attribute.name = name
                attribute.attributeType = type
                attribute.isOptional = name == "endedAt"
                return attribute
            }
            entity.uniquenessConstraints = [["id"]]
            model.entities = [entity]
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let trip = NSEntityDescription.insertNewObject(forEntityName: "Trip", into: context)
            trip.setValue(id, forKey: "id")
            trip.setValue(Date(timeIntervalSince1970: 100), forKey: "startedAt")
            trip.setValue("active", forKey: "status")
            try context.save()
            try coordinator.remove(store)
        }
        let repository = try CoreDataTripRepository(storeURL: url)
        let migrated = try repository.load()
        #expect(migrated.count == 1)
        #expect(migrated.first?.id == id)
        #expect(migrated.first?.destination == "Practice trip")
        #expect(migrated.first?.status == .active)
    }

}
