import Foundation
import Testing
@testable import GuardiaDomain

@Test func roadRouteDecodesCoordinateOrderAndGeometry() throws {
    let data = Data(#"{"code":"Ok","routes":[{"distance":4200,"duration":600,"geometry":{"type":"LineString","coordinates":[[79.86,6.92],[79.861,6.921],[79.87,6.93]]}}]}"#.utf8)
    let result = try JSONDecoder().decode(RoadRouteResponse.self, from: data).tripRoute(from: RouteCoordinate(latitude: 6.92, longitude: 79.86), to: RouteCoordinate(latitude: 6.93, longitude: 79.87), at: Date())
    #expect(result.expectedPath.count == 3)
    #expect(result.expectedPath[0].latitude == 6.92)
    #expect(result.distance == 4200)
    #expect(result.provider == "OSRM / OpenStreetMap")
}
@Test func roadRouteRejectsMissingRoute() throws {
    let response = try JSONDecoder().decode(RoadRouteResponse.self, from: Data(#"{"code":"NoRoute"}"#.utf8))
    #expect(throws: RoadRouteError.self) {
        try response.tripRoute(from: RouteCoordinate(latitude: 0, longitude: 0), to: RouteCoordinate(latitude: 0, longitude: 1), at: Date())
    }
}
@Test func roadRouteRejectsDistantGeometry() throws {
    let data = Data(#"{"code":"Ok","routes":[{"distance":100,"duration":10,"geometry":{"type":"LineString","coordinates":[[0,0],[0,1]]}}]}"#.utf8)
    let response = try JSONDecoder().decode(RoadRouteResponse.self, from: data)
    #expect(throws: RoadRouteError.self) {
        try response.tripRoute(from: RouteCoordinate(latitude: 6.92, longitude: 79.86), to: RouteCoordinate(latitude: 6.93, longitude: 79.87), at: Date())
    }
}
