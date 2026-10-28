import SwiftUI
import Combine

@MainActor
final class GuardiaStore: ObservableObject {
    @Published private(set) var contacts: [TrustedContact] = []
    @Published private(set) var trips: [TripRecord] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var message: String?
    private let contactRepository: ContactRepository
    private let repository: any TripRepository
    private let authenticator: any DeviceAuthenticating
    private var authenticationGeneration = 0

    var activeTrip: TripRecord? { trips.first { $0.status == .active } }

    init(repository: any TripRepository, authenticator: any DeviceAuthenticating, contactRepository: ContactRepository) {
        self.contactRepository = contactRepository
        self.repository = repository
        self.authenticator = authenticator
    }

    func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let generation = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.unlock(), generation == authenticationGeneration else { return }
            trips = try repository.load()
            contacts = try contactRepository.load()
            isUnlocked = true
        } catch { message = error.localizedDescription }
    }

    func lock() {
        authenticationGeneration += 1
        isUnlocked = false
        trips = []
        contacts = []
        message = nil
    }

    func startTrip(destination: String, fare: Double?) async -> Bool {
        guard isUnlocked, activeTrip == nil, !isAuthenticating else { return false }
        let name = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, fare == nil || (fare!.isFinite && fare! > 0) else { return false }
        isAuthenticating = true
        let generation = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.unlock(), generation == authenticationGeneration, isUnlocked else { return false }
            let trip = TripRecord(id: UUID(), startedAt: Date(), status: .active, destination: name, agreedFare: fare)
            try repository.save(trip)
            trips = try repository.load()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func addContact(name: String, phone: String) -> Bool {
        guard isUnlocked, contacts.count < 3, ContactValidation.isValid(name: name, phone: phone) else { return false }
        let normalized = phone.filter(\.isNumber)
        guard !contacts.contains(where: { $0.phone.filter(\.isNumber) == normalized }) else {
            message = "This phone number is already in your contacts."
            return false
        }
        do {
            try contactRepository.save(TrustedContact(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines)))
            contacts = try contactRepository.load()
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func deleteContacts(at offsets: IndexSet) {
        guard isUnlocked else { return }
        do {
            for index in offsets { try contactRepository.delete(contacts[index]) }
            contacts = try contactRepository.load()
        } catch { message = error.localizedDescription }
    }

    func finishTrip(cancelled: Bool = false) {
        guard isUnlocked, var trip = activeTrip else { return }
        do {
            try trip.finish(as: cancelled ? .cancelled : .completed, at: Date())
            persist(trip)
        } catch { message = error.localizedDescription }
    }

    private func persist(_ trip: TripRecord) {
        do {
            try repository.save(trip)
            trips = try repository.load()
        } catch { message = "Could not save or reload your trip. \(error.localizedDescription)" }
    }
}
