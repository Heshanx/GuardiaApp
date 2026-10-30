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
    private var escalationTask: Task<Void, Never>?
    private var outsideSince: Date?
    private var lastCheckIn: Date?
    let sharing = LiveSharingService()
    let liveActivity = TripLiveActivity()
    let notifications = CheckInNotifications()

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
            let restoredTrip = recordingTrip
            Task { await sharing.restore(for: restoredTrip) }
            scheduleCheckInDeadline()
        } catch { message = "Couldn’t complete that change. Please try again." }
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
            outsideSince = nil
            lastCheckIn = nil
            liveActivity.update(trip); sharing.publish(trip, force: true)
            if trip.route != nil { location.startRecording() }
            return true
        } catch { message = "Couldn’t complete that change. Please try again."; return false }
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
        } catch { message = "Couldn’t complete that change. Please try again."; return false }
    }

    func deleteContacts(at offsets: IndexSet) {
        guard isUnlocked else { return }
        do {
            for index in offsets { try contactRepository.delete(contacts[index]) }
            contacts = try contactRepository.load()
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func finishTrip(cancelled: Bool = false) {
        guard isUnlocked, var trip = activeTrip else { return }
        do {
            try trip.finish(as: cancelled ? .cancelled : .completed, at: Date())
            try repository.save(trip)
            Task { await sharing.stop() }
            liveActivity.end(trip)
            location.stopRecording()
            escalationTask?.cancel()
            notifications.clear()
            recordingTrip = nil
            trips = try repository.load()
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func resumeRecording() {
        guard isUnlocked, var trip = activeTrip, trip.route != nil, location.hasPermission else { return }
        do {
            trip.route?.recordingSessions.append(Date())
            try repository.save(trip)
            recordingTrip = trip
            liveActivity.update(trip); sharing.publish(trip, force: true)
            trips = try repository.load()
            outsideSince = nil
            location.startRecording()
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func respondToCheckIn(_ response: String) {
        guard isUnlocked, var trip = activeTrip,
              let index = trip.route?.checkIns?.firstIndex(where: { $0.response == nil }) else { return }
        trip.route?.checkIns?[index].response = response
        do {
            try repository.save(trip)
            recordingTrip = trip
            liveActivity.update(trip); sharing.publish(trip, force: true)
            trips = try repository.load()
            escalationTask?.cancel()
            notifications.clear()
            outsideSince = nil
            lastCheckIn = Date()
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func updateContact(_ contact: TrustedContact) -> Bool {
        guard isUnlocked, ContactValidation.isValid(name: contact.name, phone: contact.phone),
              contacts.contains(where: { $0.id == contact.id }) else { return false }
        guard !contacts.contains(where: { $0.id != contact.id && $0.phone.filter(\.isNumber) == contact.phone.filter(\.isNumber) }) else {
            message = "That number is already saved."; return false
        }
        do { try contactRepository.save(contact); contacts = try contactRepository.load(); return true }
        catch { message = "Couldn’t complete that change. Please try again."; return false }
    }

    func savePaidFare(tripID: UUID, amount: Double?) -> Bool {
        guard isUnlocked, var trip = trips.first(where: { $0.id == tripID }), trip.status != .active,
              amount == nil || (amount!.isFinite && amount! > 0) else { return false }
        trip.paidFare = amount
        do { try repository.save(trip); trips = try repository.load(); return true }
        catch { message = "Couldn’t complete that change. Please try again."; return false }
    }

    func deleteHistory() async {
        guard isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        let generation = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.unlock(), isUnlocked, generation == authenticationGeneration else { return }
            try repository.deleteFinished()
            trips = try repository.load()
            message = "Trip history cleared. Your current trip and contacts are kept."
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func deleteCloudData() async {
        guard isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        let version = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.unlock(), isUnlocked, version == authenticationGeneration else { return }
            try await sharing.deleteAll()
            message = "Shared links removed."
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func manualCheckIn() {
        guard isUnlocked, var trip = activeTrip else { return }
        if trip.route == nil {
            message = "This is a check-in-only trip. Call a trusted contact directly; route alerts need a recorded route."
            return
        }
        guard !(trip.route?.checkIns ?? []).contains(where: { $0.response == nil }) else { return }
        if trip.route?.checkIns == nil { trip.route?.checkIns = [] }
        trip.route?.checkIns?.append(RouteCheckIn(id: UUID(), raisedAt: Date(), distance: 0, trigger: "manual"))
        do {
            try repository.save(trip); recordingTrip = trip; liveActivity.update(trip); sharing.publish(trip, force: true); trips = try repository.load()
            scheduleCheckInDeadline()
            Task { try? await notifications.post() }
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    func escalateCheckIn() {
        guard var trip = recordingTrip, trip.status == .active,
              let index = trip.route?.checkIns?.firstIndex(where: { $0.response == nil && $0.escalatedAt == nil }) else { return }
        trip.route?.checkIns?[index].escalatedAt = Date()
        do {
            try repository.save(trip); recordingTrip = trip; liveActivity.update(trip); sharing.publish(trip, force: true)
            if isUnlocked { trips = try repository.load() }
        } catch { message = "Couldn’t complete that change. Please try again." }
    }

    private func scheduleCheckInDeadline() {
        escalationTask?.cancel()
        guard let check = recordingTrip?.route?.checkIns?.first(where: { $0.response == nil && $0.escalatedAt == nil }) else { return }
        escalationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, check.deadline.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled else { return }
            self?.escalateCheckIn()
        }
    }

    private func record(_ sample: RouteSample) {
        guard var trip = recordingTrip, trip.status == .active, sample.timestamp >= trip.startedAt,
              trip.route?.append(sample, now: Date()) == true else { return }
        let previousCount = trip.route?.checkIns?.count ?? 0
        do {
            if let previous = trip.route?.samples.dropLast().last, sample.timestamp.timeIntervalSince(previous.timestamp) > 60 { outsideSince = nil }
            if let route = trip.route, let distance = RouteCorridor.distance(from: sample.coordinate, to: route.expectedPath) {
                if distance - sample.accuracy > (DeviationSensitivity(rawValue: UserDefaults.standard.string(forKey: "deviationSensitivity") ?? "balanced") ?? .balanced).meters {
                    if let since = outsideSince, sample.timestamp.timeIntervalSince(since) >= 15,
                       lastCheckIn == nil || sample.timestamp.timeIntervalSince(lastCheckIn!) >= 300,
                       !(route.checkIns ?? []).contains(where: { $0.response == nil }) {
                        if trip.route?.checkIns == nil { trip.route?.checkIns = [] }
                        trip.route?.checkIns?.append(RouteCheckIn(id: UUID(), raisedAt: sample.timestamp, distance: distance))
                        lastCheckIn = sample.timestamp
                    }
                    if outsideSince == nil { outsideSince = sample.timestamp }
                } else { outsideSince = nil }
            }
            try repository.save(trip)
            recordingTrip = trip
            liveActivity.update(trip); sharing.publish(trip)
            if (trip.route?.checkIns?.count ?? 0) > previousCount {
                scheduleCheckInDeadline()
                Task {
                    do { try await notifications.post() }
                    catch { message = "Check-in saved, but its notification could not be displayed." }
                }
            }
            if isUnlocked, let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        } catch {
            location.stopRecording()
            message = "Your journey is paused because it couldn’t be saved. Please try again."
        }
    }
}
