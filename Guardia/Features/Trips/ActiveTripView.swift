import SwiftUI
import CoreLocation

struct ActiveTripView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    let trip: TripRecord
    @State private var confirmEnd = false
    @State private var fullMap = false
    @State private var confirmAlert = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    init(store: GuardiaStore, trip: TripRecord) { self.store = store; self.location = store.location; self.trip = trip }
    var body: some View {
        let layout = sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
        layout {
            if let route = trip.route {
                VStack {
                    TripRouteMap(route: route, showsUser: location.isRecording, height: sizeClass == .regular ? 560 : 420)
                    Button { fullMap = true } label: { Label("Full-screen map", systemImage: "arrow.up.left.and.arrow.down.right") }
                }

            }
            GuardiaCard {
                Label(location.isRecording ? "Recording your route" : "Trip in progress", systemImage: "location.circle.fill").font(.headline)
                Text(trip.destination).font(.title.bold())
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(trip.startedAt, style: .timer).font(.title.monospacedDigit()) }
                if let fare = trip.agreedFare { Text(fare, format: .currency(code: "LKR")) }
                if let route = trip.route {
                    Label("\(route.samples.count) saved locations", systemImage: "location").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Planned journey", value: "\(max(1, Int(route.expectedTravelTime / 60))) min")
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        Text(location.isRecording && location.freshSample == nil ? "Waiting for a fresh location fix…" : location.status)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !location.isRecording {
                        Text("Recording is paused. After relaunch, resume here; missing locations cannot be recovered.").font(.footnote)
                        if location.authorization == .notDetermined {
                            Button("Allow location access") { location.beginPreview() }
                        } else if location.needsSettings {
                            Button("Open location settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        } else {
                            Button("Resume recording") { store.resumeRecording() }.disabled(!location.hasPermission)
                        }
                    }
                } else { Text("This earlier trip contains check-in details only.").font(.footnote) }
                LiveSharingPanel(store: store)
                Button("Raise manual check-in", role: .destructive) { confirmAlert = true }
                Button("End trip") { confirmEnd = true }.buttonStyle(.borderedProminent)
            }
        }
        .fullScreenCover(isPresented: $fullMap) { FullTripMapView(store: store) }
        .confirmationDialog("Raise a manual route check-in?", isPresented: $confirmAlert, titleVisibility: .visible) {
            Button("Raise check-in") { store.manualCheckIn() }
        } message: { Text("Uses the same check-in and countdown as a route deviation. This does not call emergency services.") }
        .sheet(item: Binding(get: { fullMap ? nil : trip.route?.checkIns?.first(where: { $0.response == nil }) }, set: { _ in })) { check in
            RouteCheckInSheet(store: store, check: check).presentationDetents([.medium, .large]).presentationDragIndicator(.visible).interactiveDismissDisabled()
        }
        .onDisappear { location.endPreview() }
        .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("I've arrived") { store.finishTrip() }
            Button("Cancel trip", role: .destructive) { store.finishTrip(cancelled: true) }
        }
    }
}
