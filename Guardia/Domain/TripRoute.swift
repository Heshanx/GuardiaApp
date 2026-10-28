import Foundation

struct RouteCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }

    func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let a = latitude * radians, b = other.latitude * radians
        let dLat = b - a, dLon = (other.longitude - longitude) * radians
        let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}

struct RouteSample: Codable, Equatable, Sendable {
    let coordinate: RouteCoordinate
    let timestamp: Date
    let accuracy: Double

    func isUsable(at now: Date) -> Bool {
        coordinate.isValid && accuracy.isFinite && (0...100).contains(accuracy) &&
        now.timeIntervalSince(timestamp) >= -5 && now.timeIntervalSince(timestamp) <= 30
    }
}

struct TripRoute: Codable, Equatable, Sendable {
    let origin: RouteCoordinate
    let destination: RouteCoordinate
    let expectedPath: [RouteCoordinate]
    let distance: Double
    let expectedTravelTime: Double
    let plannedAt: Date
    var samples: [RouteSample] = []
    var recordingSessions: [Date] = []

    var recordedDistance: Double {
        zip(samples, samples.dropFirst()).reduce(0) { result, pair in
            // A gap is not a recorded road segment.
            guard !hasGap(from: pair.0.timestamp, to: pair.1.timestamp) else { return result }
            return result + pair.0.coordinate.distance(to: pair.1.coordinate)
        }
    }

    func hasGap(from start: Date, to end: Date) -> Bool {
        end.timeIntervalSince(start) > 120 || recordingSessions.contains { $0 > start && $0 <= end }
    }

    mutating func append(_ sample: RouteSample, now: Date) -> Bool {
        guard sample.isUsable(at: now) else { return false }
        if let last = samples.last {
            let elapsed = sample.timestamp.timeIntervalSince(last.timestamp)
            let distance = sample.coordinate.distance(to: last.coordinate)
            guard elapsed > 0, distance / elapsed <= 80,
                  distance >= 10 || elapsed >= 30 else { return false }
        }
        samples.append(sample)
        return true
    }

    func canStart(from sample: RouteSample, now: Date) -> Bool {
        sample.isUsable(at: now) && now.timeIntervalSince(plannedAt) <= 300 &&
        now >= plannedAt && origin.distance(to: sample.coordinate) <= 200
    }
}
