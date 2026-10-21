#if compiler(>=6.0)
import Foundation
import Testing
@testable import GuardiaDomain

@Test func tripCompletionPreservesStartAndSetsEnd() throws {
    let start = Date(timeIntervalSince1970: 100)
    var trip = TripRecord(id: UUID(), startedAt: start, status: .active)
    try trip.finish(as: .completed, at: start.addingTimeInterval(60))
    #expect(trip.status == .completed)
    #expect(trip.startedAt == start)
    #expect(trip.endedAt == start.addingTimeInterval(60))
}

@Test(arguments: [TripStatus.completed, .cancelled])
func finishedTripsCannotTransitionAgain(status: TripStatus) throws {
    let start = Date(timeIntervalSince1970: 100)
    var trip = TripRecord(id: UUID(), startedAt: start, status: .active)
    try trip.finish(as: status, at: start)
    #expect(throws: TripTransitionError.self) { try trip.finish(as: .completed, at: start) }
    #expect(trip.status == status)
}

@Test func invalidTransitionsDoNotMutateTrip() {
    let start = Date(timeIntervalSince1970: 100)
    var trip = TripRecord(id: UUID(), startedAt: start, status: .active)
    #expect(throws: TripTransitionError.self) { try trip.finish(as: .completed, at: start.addingTimeInterval(-1)) }
    #expect(throws: TripTransitionError.self) { try trip.finish(as: .active, at: start) }
    #expect(trip.status == .active)
    #expect(trip.endedAt == nil)
}
#endif
