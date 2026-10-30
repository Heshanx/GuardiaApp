import Foundation
import Combine
import CoreLocation

@MainActor
final class TripLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var latest: RouteSample?
    @Published private(set) var isRecording = false
    @Published private(set) var status = "Location is off."
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    var onSample: ((RouteSample) -> Void)?
    private let manager = CLLocationManager()
    private var previewing = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var hasPermission: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var freshSample: RouteSample? { latest.flatMap { $0.isUsable(at: Date()) ? $0 : nil } }
    var needsSettings: Bool { authorization == .denied || authorization == .restricted }

    func beginPreview() {
        previewing = true
        if !isRecording { manager.distanceFilter = kCLDistanceFilterNone }
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        refresh()
    }

    func endPreview() {
        previewing = false
        if !isRecording { manager.stopUpdatingLocation(); latest = nil; status = "Location is off." }
    }

    func startRecording() {
        guard hasPermission else { status = "Allow location access in Settings to record your route."; return }
        isRecording = true
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        refresh()
    }

    func stopRecording() {
        isRecording = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        if !previewing { manager.stopUpdatingLocation(); latest = nil; status = "Location is off." }
    }

    private func refresh() {
        guard hasPermission else {
            status = needsSettings ? "Location access is off. Open Settings to allow it." : "Allow location access to plan a route."
            return
        }
        if manager.accuracyAuthorization == .reducedAccuracy {
            status = "Precise Location is off. Enable it in Settings for reliable route recording."
        } else { status = freshSample == nil ? "Finding your current location…" : "Location ready" }
        if previewing || isRecording { manager.startUpdatingLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if !hasPermission {
            isRecording = false
            manager.allowsBackgroundLocationUpdates = false
            manager.stopUpdatingLocation()
            latest = nil
        }
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let sample = RouteSample(coordinate: RouteCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude), timestamp: location.timestamp, accuracy: location.horizontalAccuracy)
            guard sample.isUsable(at: Date()), latest == nil || sample.timestamp > latest!.timestamp else { continue }
            latest = sample
            status = "Location ready · ±\(Int(sample.accuracy)) m"
            if isRecording { onSample?(sample) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let failure = error as? CLError, failure.code == .locationUnknown {
            status = "Waiting for a reliable location signal…"
        } else { status = error.localizedDescription }
    }
}
