import SwiftUI
import CoreLocation

struct ActiveTripView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    let trip: TripRecord
    @State private var confirmEnd = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    init(store: GuardiaStore, trip: TripRecord) { self.store = store; self.location = store.location; self.trip = trip }
    var body: some View {
        let layout = sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
        layout {
            if let route = trip.route {
                TripRouteMap(route: route, showsUser: location.isRecording, height: sizeClass == .regular ? 560 : 420)

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
                Text("Route check-ins are saved locally. Contacts are not notified.").font(.footnote).foregroundStyle(.secondary)
                Button("End trip") { confirmEnd = true }.buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: Binding(get: { trip.route?.checkIns?.first(where: { $0.response == nil }) }, set: { _ in })) { check in
            RouteCheckInSheet(store: store, check: check).presentationDetents([.medium, .large]).presentationDragIndicator(.visible).interactiveDismissDisabled()
        }
        .onDisappear { location.endPreview() }
        .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("I've arrived") { store.finishTrip() }
            Button("Cancel trip", role: .destructive) { store.finishTrip(cancelled: true) }
        }
    }
}
