import Testing
@testable import GuardiaDomain

@Test func measuresSegmentInteriorRatherThanEndpoints() throws {
    let path = [RouteCoordinate(latitude: 0, longitude: 0), RouteCoordinate(latitude: 0, longitude: 0.02)]
    let distance = try #require(RouteCorridor.distance(from: RouteCoordinate(latitude: 0.001, longitude: 0.01), to: path))
    #expect(distance > 110 && distance < 112)
}
@Test func clampsBeyondEndpointAndHandlesRepeatedVertices() throws {
    let point = RouteCoordinate(latitude: 0, longitude: 0)
    #expect(RouteCorridor.distance(from: point, to: [point, point]) == 0)
    let distance = try #require(RouteCorridor.distance(from: RouteCoordinate(latitude: 0, longitude: 0.02), to: [point, RouteCoordinate(latitude: 0, longitude: 0.01)]))
    #expect(distance > 1100 && distance < 1120)
    #expect(RouteCorridor.distance(from: point, to: []) == nil)
}
