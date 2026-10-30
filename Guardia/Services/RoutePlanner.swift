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
    private var roadTask: Task<TripRoute, Error>?

    func clear() {
        generation += 1
        search?.cancel(); directions?.cancel(); roadTask?.cancel()
        if !results.isEmpty { results = [] }
        if route != nil { route = nil }
        if destinationName != nil { destinationName = nil }
        if error != nil { error = nil }
        if isBusy { isBusy = false }
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
            results = Array(response.mapItems.prefix(6))
            if results.isEmpty { error = "No places found. Try a town, address or landmark." }
        } catch {
            guard token == generation else { return }
            self.error = "Could not search places. Check your connection and try again."
        }
    }

    func plan(to item: MKMapItem, from sample: RouteSample) async {
        generation += 1
        search?.cancel(); directions?.cancel(); roadTask?.cancel()
        route = nil; error = nil
        let token = generation
        destinationName = item.name ?? "Destination"
        isBusy = true
        defer { if token == generation { isBusy = false } }
        let origin = sample.coordinate
        let destination = RouteCoordinate(item.location.coordinate)
        let task = Task { try await RoadRoutingService().route(from: origin, to: destination) }
        roadTask = task
        do {
            let planned = try await task.value
            guard token == generation else { return }
            route = planned
        } catch {
            guard token == generation else { return }
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            self.error = "A route isn’t available right now. Try again or continue without one."
        }
    }
}
