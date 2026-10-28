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
    let location: TripLocationService
    private var recordingTrip: TripRecord?

    var activeTrip: TripRecord? { trips.first { $0.status == .active } }

    init(repository: any TripRepository, authenticator: any DeviceAuthenticating, contactRepository: ContactRepository, location: TripLocationService) {
        self.location = location
        self.contactRepository = contactRepository
        self.repository = repository
        self.authenticator = authenticator
        location.onSample = { [weak self] sample in self?.record(sample) }
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
            recordingTrip = activeTrip
        } catch { message = error.localizedDescription }
    }

    func lock() {
        authenticationGeneration += 1
        isUnlocked = false
        trips = []
        contacts = []
        message = nil
    }

    func startTrip(destination: String, fare: Double?, route: TripRoute? = nil) async -> Bool {
        guard isUnlocked, activeTrip == nil, !isAuthenticating else { return false }
        let name = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, fare == nil || (fare!.isFinite && fare! > 0) else { return false }
        isAuthenticating = true
        let generation = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.unlock(), generation == authenticationGeneration, isUnlocked else { return false }
            if let route {
                guard let sample = location.freshSample, route.canStart(from: sample, now: Date()) else {
                    message = "Your location or route preview has changed. Refresh the route before starting."
                    return false
                }
            }
            var trip = TripRecord(id: UUID(), startedAt: Date(), status: .active, destination: name, agreedFare: fare, route: route)
            if trip.route != nil { trip.route?.recordingSessions.append(Date()) }
            try repository.save(trip)
            trips = try repository.load()
            recordingTrip = trip
            if trip.route != nil { location.startRecording() }
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
            try repository.save(trip)
            location.stopRecording()
            recordingTrip = nil
            trips = try repository.load()
        } catch { message = error.localizedDescription }
    }

    func resumeRecording() {
        guard isUnlocked, var trip = activeTrip, trip.route != nil, location.hasPermission else { return }
        do {
            trip.route?.recordingSessions.append(Date())
            try repository.save(trip)
            recordingTrip = trip
            trips = try repository.load()
            location.startRecording()
        } catch { message = error.localizedDescription }
    }

    private func record(_ sample: RouteSample) {
        guard var trip = recordingTrip, trip.status == .active, sample.timestamp >= trip.startedAt,
              trip.route?.append(sample, now: Date()) == true else { return }
        do {
            try repository.save(trip)
            recordingTrip = trip
            if isUnlocked, let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        } catch {
            location.stopRecording()
            message = "Route recording paused because the location could not be saved. \(error.localizedDescription)"
        }
    }
}
