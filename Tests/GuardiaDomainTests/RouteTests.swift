import Foundation
import Testing
@testable import GuardiaDomain

private let now = Date(timeIntervalSince1970: 1000)
private let origin = RouteCoordinate(latitude: 6.9, longitude: 79.86)
private func route() -> TripRoute {
    TripRoute(origin: origin, destination: RouteCoordinate(latitude: 6.91, longitude: 79.87), expectedPath: [origin], distance: 2000, expectedTravelTime: 600, plannedAt: now)
}
private func sample(_ time: Date, latitude: Double = 6.9, accuracy: Double = 10) -> RouteSample {
    RouteSample(coordinate: RouteCoordinate(latitude: latitude, longitude: 79.86), timestamp: time, accuracy: accuracy)
}

@Test func rejectsStaleAndInaccurateLocations() {
    #expect(!sample(now.addingTimeInterval(-31)).isUsable(at: now))
    #expect(!sample(now.addingTimeInterval(6)).isUsable(at: now))
    #expect(!sample(now, accuracy: -1).isUsable(at: now))
    #expect(!sample(now, accuracy: 101).isUsable(at: now))
    #expect(!sample(now, latitude: 91).isUsable(at: now))
    #expect(sample(now, accuracy: 100).isUsable(at: now))
}

@Test func recordingRejectsDuplicatesJitterAndImpossibleJumps() {
    var trip = route()
    let result1 = trip.append(sample(now), now: now)
    #expect(result1)
    let result2 = trip.append(sample(now), now: now)
    #expect(!result2)
    let result3 = trip.append(sample(now.addingTimeInterval(-1)), now: now)
    #expect(!result3)
    let result4 = trip.append(sample(now.addingTimeInterval(1), latitude: 6.90001), now: now.addingTimeInterval(1))
    #expect(!result4)
    let result5 = trip.append(sample(now.addingTimeInterval(1), latitude: 7.9), now: now.addingTimeInterval(1))
    #expect(!result5)
    let result6 = trip.append(sample(now.addingTimeInterval(10), latitude: 6.9002), now: now.addingTimeInterval(10))
    #expect(result6)
    #expect(trip.samples.count == 2)
}

@Test func stationaryLocationIsRetainedAfterThirtySeconds() {
    var trip = route()
    let result7 = trip.append(sample(now), now: now)
    #expect(result7)
    let result8 = trip.append(sample(now.addingTimeInterval(30)), now: now.addingTimeInterval(30))
    #expect(result8)
}

@Test func stalePreviewOrMovedOriginRequiresReplanning() {
    let trip = route()
    #expect(trip.canStart(from: sample(now), now: now))
    #expect(!trip.canStart(from: sample(now, latitude: 6.91), now: now))
    let later = now.addingTimeInterval(301)
    #expect(!trip.canStart(from: sample(later), now: later))
}

@Test func recordingGapsAreNotCountedAsTravel() {
    var trip = route()
    trip.samples = [sample(now), sample(now.addingTimeInterval(180), latitude: 6.91)]
    #expect(trip.recordedDistance == 0)
    trip.samples = [sample(now), sample(now.addingTimeInterval(30), latitude: 6.9002)]
    #expect(trip.recordedDistance > 20)
    trip.recordingSessions = [now.addingTimeInterval(10)]
    #expect(trip.recordedDistance == 0)
}

@Test func routePayloadRoundTripsIncludingSessions() throws {
    var trip = route()
    trip.samples = [sample(now)]
    trip.recordingSessions = [now]
    #expect(try JSONDecoder().decode(TripRoute.self, from: JSONEncoder().encode(trip)) == trip)
}
