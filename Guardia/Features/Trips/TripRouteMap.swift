import SwiftUI
import MapKit

struct TripRouteMap: View {
    let route: TripRoute
    var showsUser = false
    var height: CGFloat = 300
    var body: some View {
        Map {
            MapPolyline(coordinates: route.expectedPath.map(\.mapCoordinate)).stroke(GuardiaStyle.accent.opacity(0.18), lineWidth: 24)
            MapPolyline(coordinates: route.expectedPath.map(\.mapCoordinate)).stroke(GuardiaStyle.accent, lineWidth: 4)
            ForEach(Array(recordedSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate.mapCoordinate)).stroke(.green, lineWidth: 4)
            }
            Marker("Start", systemImage: "circle", coordinate: route.origin.mapCoordinate).tint(GuardiaStyle.accent)
            Marker("Destination", coordinate: route.destination.mapCoordinate).tint(.orange)
            if showsUser { UserAnnotation() }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityLabel("Trip map. Blue shows the planned driving route. Green shows recorded locations.")
    }
    private var recordedSegments: [[RouteSample]] {
        var segments: [[RouteSample]] = []
        for sample in route.samples {
            if let last = segments.last?.last, !route.hasGap(from: last.timestamp, to: sample.timestamp) {
                segments[segments.count - 1].append(sample)
            } else { segments.append([sample]) }
        }
        return segments.filter { $0.count > 1 }
    }
}
