import Foundation

/// Local tangent-plane projection measures distance to road segments, not route vertices.
enum RouteCorridor {
    static func distance(from point: RouteCoordinate, to path: [RouteCoordinate]) -> Double? {
        guard point.isValid, path.count >= 2, path.allSatisfy({ $0.isValid }) else { return nil }
        let scale = Double.pi / 180 * 6_371_000
        let longitudeScale = scale * cos(point.latitude * .pi / 180)
        func xy(_ p: RouteCoordinate) -> (Double, Double) {
            var delta = p.longitude - point.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return (delta * longitudeScale, (p.latitude - point.latitude) * scale)
        }
        return zip(path, path.dropFirst()).map { start, end in
            let (ax, ay) = xy(start), (bx, by) = xy(end)
            let dx = bx - ax, dy = by - ay
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : min(1, max(0, -(ax * dx + ay * dy) / length))
            return hypot(ax + t * dx, ay + t * dy)
        }.min()
    }
}
