import Foundation

/// Public OSRM endpoint for coursework testing. A production deployment requires
/// managed/self-hosted routing. Sends endpoints only, never the recorded GPS trace.
struct RoadRoutingService {
    func route(from origin: RouteCoordinate, to destination: RouteCoordinate) async throws -> TripRoute {
        let coordinates = "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
        guard let url = URL(string: "https://router.project-osrm.org/route/v1/driving/\(coordinates)?overview=full&geometries=geojson&steps=false&alternatives=false") else { throw RoadRouteError.noRoute }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Guardia-iOS-Coursework/0.3", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw RoadRouteError.serviceUnavailable }
        guard response.statusCode == 200 else {
            if let result = try? JSONDecoder().decode(RoadRouteResponse.self, from: data), ["NoRoute", "NoSegment"].contains(result.code) { throw RoadRouteError.noRoute }
            throw RoadRouteError.serviceUnavailable
        }
        return try JSONDecoder().decode(RoadRouteResponse.self, from: data).tripRoute(from: origin, to: destination, at: Date())
    }
}
