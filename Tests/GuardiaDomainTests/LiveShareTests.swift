import Foundation
import Testing
@testable import GuardiaDomain

@Suite("Live-sharing payload")
struct LiveShareTests {
    let now = Date(timeIntervalSince1970: 10000)
    func trip(pathCount: Int = 2) -> TripRecord {
        let path = (0..<pathCount).map { RouteCoordinate(latitude: 6.9 + Double($0) / 100000, longitude: 79.8) }
        let origin = RouteCoordinate(latitude: 6.9, longitude: 79.8)
        let route = TripRoute(origin: origin, destination: path.last ?? origin, expectedPath: path, distance: 1000, expectedTravelTime: 300, plannedAt: now.addingTimeInterval(-30))
        return TripRecord(id: UUID(), startedAt: now.addingTimeInterval(-100000), status: .active, destination: "Synthetic test", agreedFare: 500, route: route)
    }
    @Test func oldTripUsesNewSessionExpiryAndRealGPSTime() throws {
        var trip = trip()
        let fix = now.addingTimeInterval(-40)
        let origin = trip.route!.origin
        trip.route?.samples = [RouteSample(coordinate: origin, timestamp: fix, accuracy: 10)]
        let expiry = now.addingTimeInterval(3600)
        let fields = try LiveSharePayload.fields(trip: trip, owner: "owner", expiresAt: expiry, now: now)
        #expect((fields["expiresAt"] as? [String:String])?["timestampValue"] == ISO8601DateFormatter().string(from: expiry))
        #expect((fields["locationAt"] as? [String:String])?["timestampValue"] == ISO8601DateFormatter().string(from: fix))
        #expect((fields["updatedAt"] as? [String:String])?["timestampValue"] != (fields["locationAt"] as? [String:String])?["timestampValue"])
    }
    @Test func routeDownsamplingPreservesEndpoints() throws {
        let trip = trip(pathCount: 10001)
        let fields = try LiveSharePayload.fields(trip: trip, owner: "owner", expiresAt: now.addingTimeInterval(3600), now: now)
        let route = try #require((fields["route"] as? [String:Any])?["arrayValue"] as? [String:Any])
        let values = try #require(route["values"] as? [[String:Any]])
        #expect(values.count == 1000)
        let lastMap = try #require(values.last?["mapValue"] as? [String:Any])
        let lastFields = try #require(lastMap["fields"] as? [String:[String:Double]])
        #expect(lastFields["lat"]?["doubleValue"] == trip.route?.expectedPath.last?.latitude)
    }
    @Test func checkInAndEscalationStates() throws {
        var trip = trip()
        trip.route?.checkIns = [RouteCheckIn(id: UUID(), raisedAt: now, distance: 200)]
        func state(_ trip: TripRecord) throws -> String? {
            (try LiveSharePayload.fields(trip: trip, owner: "owner", expiresAt: now.addingTimeInterval(3600), now: now)["state"] as? [String:String])?["stringValue"]
        }
        #expect(try state(trip) == "check_in")
        trip.route?.checkIns?[0].escalatedAt = now
        #expect(try state(trip) == "help_requested")
        trip.route?.checkIns?[0].response = "Confirmed okay"
        #expect(try state(trip) == "active")
    }
    @Test func invalidOrFinishedTripCannotBeShared() {
        var finished = trip(); finished.status = .completed
        #expect(throws: (any Error).self) { try LiveSharePayload.fields(trip: finished, owner: "owner", expiresAt: now.addingTimeInterval(3600), now: now) }
        #expect(throws: (any Error).self) { try LiveSharePayload.fields(trip: trip(), owner: "owner", expiresAt: now, now: now) }
    }
    @Test func missingRouteDoesNotInventGPSOrPrivateContactData() throws {
        var trip = trip(); trip.route = nil
        let fields = try LiveSharePayload.fields(trip: trip, owner: "owner", expiresAt: now.addingTimeInterval(3600), now: now)
        #expect(fields["lat"] == nil && fields["lon"] == nil && fields["locationAt"] == nil)
        #expect(fields["contacts"] == nil && fields["phone"] == nil)
    }
}
