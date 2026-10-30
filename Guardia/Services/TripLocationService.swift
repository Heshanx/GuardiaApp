import Foundation
import Combine
import CoreLocation
import UserNotifications

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


/// Independent of the authenticated UI and continuous route recording.
/// Only a trip identifier and destination are retained for background delivery.
@MainActor
final class DestinationGeofence: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = DestinationGeofence()
    private let manager = CLLocationManager()
    private let storageKey = "guardia.destinationGeofence"
    private let prefix = "guardia.destination."
    private var context: Context?
    private struct Context: Codable {
        let tripID: UUID
        let destination: RouteCoordinate
        var notified: Bool = false
    }
    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            context = try? JSONDecoder().decode(Context.self, from: data)
        }
        manager.delegate = self
    }
    func restore() { registerIfAuthorized() }

    func start(tripID: UUID, destination: RouteCoordinate, requestPermission: Bool = true) {
        guard destination.isValid else { return }
        if context?.tripID != tripID {
            stop()
            context = Context(tripID: tripID, destination: destination)
            persist()
        }
        if requestPermission {
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
        }
        registerIfAuthorized()
    }
    func stop() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) {
            manager.stopMonitoring(for: region)
        }
        if let context {
            let identifier = prefix + context.tripID.uuidString
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        context = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    private func persist() {
        if let context, let data = try? JSONEncoder().encode(context) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    private func registerIfAuthorized() {
        guard let context, !context.notified,
              manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              manager.maximumRegionMonitoringDistance > 0 else { return }
        let identifier = prefix + context.tripID.uuidString
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) && region.identifier != identifier {
            manager.stopMonitoring(for: region)
        }
        if let existing = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            manager.requestState(for: existing)
            return
        }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: context.destination.latitude, longitude: context.destination.longitude),
            radius: min(100, manager.maximumRegionMonitoringDistance), identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .authorizedAlways {
            for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) {
                manager.stopMonitoring(for: region)
            }
        } else { registerIfAuthorized() }
    }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        manager.requestState(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { arrived(region) }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside { arrived(region) }
    }
    private func arrived(_ region: CLRegion) {
        guard var current = context, !current.notified,
              region.identifier == prefix + current.tripID.uuidString else { return }
        current.notified = true
        context = current
        persist()
        manager.stopMonitoring(for: region)
        let content = UNMutableNotificationContent()
        content.title = "Guardia arrival"
        content.body = "You are near your destination. Open Guardia to confirm arrival and end your trip."
        content.sound = .default
        // Stable identifier prevents duplicate alerts; no destination name appears on the lock screen.
        let tripID = current.tripID
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: region.identifier, content: content, trigger: nil)) { error in
                if error != nil {
                    Task { @MainActor in
                        guard self.context?.tripID == tripID else { return }
                        self.context?.notified = false
                        self.persist()
                    }
                }
            }
    }
}
