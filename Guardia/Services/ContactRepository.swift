import CoreData

@MainActor
final class ContactRepository {
    private let container: NSPersistentContainer

    init(storeURL: URL? = nil) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "TrustedContact"
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("name", .stringAttributeType), ("phone", .stringAttributeType)].map { name, type in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            return attribute
        }
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "GuardiaContacts", managedObjectModel: model)
        let directory = NSPersistentContainer.defaultDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let description = NSPersistentStoreDescription(url: storeURL ?? directory.appendingPathComponent("GuardiaContacts.sqlite"))
        description.shouldAddStoreAsynchronously = false
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
    }

    func load() throws -> [TrustedContact] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrustedContact")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try container.viewContext.fetch(request).map { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let name = object.value(forKey: "name") as? String,
                  let phone = object.value(forKey: "phone") as? String else { throw CocoaError(.fileReadCorruptFile) }
            return TrustedContact(id: id, name: name, phone: phone)
        }
    }

    func save(_ contact: TrustedContact) throws {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrustedContact")
        request.predicate = NSPredicate(format: "id == %@", contact.id as NSUUID)
        let object = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "TrustedContact", into: context)
        object.setValue(contact.id, forKey: "id")
        object.setValue(contact.name, forKey: "name")
        object.setValue(contact.phone, forKey: "phone")
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func delete(_ contact: TrustedContact) throws {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrustedContact")
        request.predicate = NSPredicate(format: "id == %@", contact.id as NSUUID)
        for object in try context.fetch(request) { context.delete(object) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
