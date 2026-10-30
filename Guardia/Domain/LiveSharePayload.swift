import Foundation

/// firestore payload builder
enum LiveSharePayload {
    static func fields(trip: TripRecord, owner: String, expiresAt: Date, now: Date) throws -> [String: Any] {
        guard trip.status == .active, !owner.isEmpty,
              !trip.destination.isEmpty, trip.destination.count <= 500,
              expiresAt > now else { throw ValidationError.invalidTrip }
        func string(_ value: String) -> [String: Any] { ["stringValue": value] }
        func number(_ value: Double) -> [String: Any] { ["doubleValue": value] }
        func timestamp(_ value: Date) -> [String: Any] { ["timestampValue": ISO8601DateFormatter().string(from: value)] }
        let event = trip.route?.checkIns?.last
        let state: String
        if event?.escalatedAt != nil, event?.response != "Confirmed okay" { state = "help_requested" }
        else if let event, event.response == nil { state = "check_in" }
        else { state = "active" }
        var fields: [String: Any] = ["ownerUid": string(owner), "destination": string(trip.destination),
            "state": string(state), "updatedAt": timestamp(now), "expiresAt": timestamp(expiresAt)]
        let original = trip.route?.expectedPath ?? []
        guard original.allSatisfy(\.isValid) else { throw ValidationError.invalidCoordinate }

        let count = min(1000, original.count)
        let overview: [RouteCoordinate] = (0..<count).map { index in
            original[count <= 1 ? 0 : Int(Double(index) * Double(original.count - 1) / Double(count - 1))]
        }
        fields["route"] = ["arrayValue": ["values": overview.map { point in
            ["mapValue": ["fields": ["lat": number(point.latitude), "lon": number(point.longitude)]]]
        }]]

        if let latest = trip.route?.samples.last {
            guard latest.coordinate.isValid else { throw ValidationError.invalidCoordinate }
            fields["lat"] = number(latest.coordinate.latitude); fields["lon"] = number(latest.coordinate.longitude)
            fields["locationAt"] = timestamp(latest.timestamp)
        } else if let route = trip.route {
            guard route.origin.isValid else { throw ValidationError.invalidCoordinate }
            fields["lat"] = number(route.origin.latitude); fields["lon"] = number(route.origin.longitude)
            fields["locationAt"] = timestamp(route.plannedAt)
        }
        if let fare = trip.agreedFare {
            guard fare.isFinite, fare > 0 else { throw ValidationError.invalidFare }
            fields["agreedFare"] = number(fare)
        }
        return fields
    }
    enum ValidationError: LocalizedError {
        case invalidTrip, invalidCoordinate, invalidFare
        var errorDescription: String? {
            switch self {
            case .invalidTrip: return "This trip cannot be shared. Check its destination and start a new sharing session."
            case .invalidCoordinate: return "The trip contains an invalid location. Refresh the route before sharing."
            case .invalidFare: return "The agreed fare is invalid."
            }
        }
    }
}
