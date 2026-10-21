import SwiftUI

@MainActor
final class GuardiaStore: ObservableObject {
    @Published private(set) var trips: [TripRecord] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var message: String?
    private let repository: any TripRepository
    private let authenticator: any DeviceAuthenticating
    private var authenticationGeneration = 0

    var activeTrip: TripRecord? { trips.first { $0.status == .active } }

    init(repository: any TripRepository, authenticator: any DeviceAuthenticating) {
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
            isUnlocked = true
        } catch { message = error.localizedDescription }
    }

    func lock() {
        authenticationGeneration += 1
        isUnlocked = false
        trips = []
        message = nil
    }

    func startPracticeTrip() {
        guard isUnlocked, activeTrip == nil else { return }
        persist(TripRecord(id: UUID(), startedAt: Date(), status: .active))
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
