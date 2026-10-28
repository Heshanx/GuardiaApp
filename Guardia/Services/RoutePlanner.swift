import MapKit
import Combine

extension RouteCoordinate {
    var mapCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ value: CLLocationCoordinate2D) { self.init(latitude: value.latitude, longitude: value.longitude) }
}

@MainActor
final class RoutePlanner: ObservableObject {
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var route: TripRoute?
    @Published private(set) var destinationName: String?
    @Published private(set) var isBusy = false
    @Published private(set) var error: String?
    private var generation = 0
    private var search: MKLocalSearch?
    private var directions: MKDirections?

    func clear() {
        generation += 1
        search?.cancel(); directions?.cancel()
        results = []; route = nil; destinationName = nil; error = nil; isBusy = false
    }

    func searchPlaces(_ query: String, from origin: RouteSample?) async {
        clear()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let token = generation
        isBusy = true
        defer { if token == generation { isBusy = false } }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let origin {
            request.region = MKCoordinateRegion(center: origin.coordinate.mapCoordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard token == generation else { return }
            results = response.mapItems
            if results.isEmpty { error = "No places found. Try a town, address or landmark." }
        } catch {
            guard token == generation else { return }
            self.error = "Could not search places. Check your connection and try again."
        }
    }

    func plan(to item: MKMapItem, from sample: RouteSample) async {
        clear()
        let token = generation
        isBusy = true
        defer { if token == generation { isBusy = false } }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude), address: nil)
        request.destination = item
        request.transportType = .automobile
        let operation = MKDirections(request: request)
        directions = operation
        do {
            let response = try await operation.calculate()
            guard token == generation else { return }
            guard let result = response.routes.first else { error = "No driving route is available for this destination."; return }
            var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: result.polyline.pointCount)
            result.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            guard coordinates.count >= 2 else { error = "The route is incomplete. Choose another destination."; return }
            route = TripRoute(origin: sample.coordinate, destination: RouteCoordinate(item.location.coordinate), expectedPath: coordinates.map(RouteCoordinate.init), distance: result.distance, expectedTravelTime: result.expectedTravelTime, plannedAt: Date())
            destinationName = item.name ?? "Destination"
        } catch {
            guard token == generation else { return }
            self.error = "Could not calculate a driving route. Check your connection or choose another destination."
        }
    }
}
