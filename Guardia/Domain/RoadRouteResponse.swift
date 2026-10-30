import Foundation

struct RoadRouteResponse: Decodable {
    struct Road: Decodable {
        struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
        let distance: Double
        let duration: Double
        let geometry: Geometry
    }
    let code: String
    let routes: [Road]?
    func tripRoute(from origin: RouteCoordinate, to destination: RouteCoordinate, at date: Date) throws -> TripRoute {
        guard code == "Ok", let road = routes?.first, road.distance.isFinite, road.distance > 0,
              road.duration.isFinite, road.duration > 0, road.geometry.type == "LineString",
              road.geometry.coordinates.count >= 2 else { throw RoadRouteError.noRoute }
        let path = try road.geometry.coordinates.map { pair -> RouteCoordinate in
            guard pair.count >= 2 else { throw RoadRouteError.invalidGeometry }
            let point = RouteCoordinate(latitude: pair[1], longitude: pair[0])
            guard point.isValid else { throw RoadRouteError.invalidGeometry }
            return point
        }
        guard let first = path.first, let last = path.last,
              first.distance(to: origin) <= 1000, last.distance(to: destination) <= 1000 else { throw RoadRouteError.invalidGeometry }
        return TripRoute(origin: origin, destination: destination, expectedPath: path,
                         distance: road.distance, expectedTravelTime: road.duration, plannedAt: date,
                         provider: "OSRM / OpenStreetMap")
    }
}

enum RoadRouteError: LocalizedError {
    case noRoute, invalidGeometry, serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .noRoute: return "No driving route found. Try a nearby road or entrance."
        case .invalidGeometry: return "Road geometry is incomplete or too far from your selected points. Try a nearby entrance."
        case .serviceUnavailable: return "The routing service is unavailable. Please retry shortly."
        }
    }
}
