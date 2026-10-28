import SwiftUI
import CoreLocation

struct ActiveTripView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    let trip: TripRecord
    @State private var confirmEnd = false
    init(store: GuardiaStore, trip: TripRecord) { self.store = store; self.location = store.location; self.trip = trip }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let route = trip.route {
                TripRouteMap(route: route, showsUser: location.isRecording)
                Text("Blue: planned route · Green: recorded path").font(.caption).foregroundStyle(.secondary)
            }
            GuardiaCard {
                Label(location.isRecording ? "Recording your route" : "Trip in progress", systemImage: "location.circle.fill").font(.headline)
                Text(trip.destination).font(.title.bold())
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(trip.startedAt, style: .timer).font(.title.monospacedDigit()) }
                if let fare = trip.agreedFare { Text(fare, format: .currency(code: "LKR")) }
                if let route = trip.route {
                    Text("\(route.samples.count) location points saved").font(.subheadline)
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
                Text("Route deviation checks and contact alerts are not enabled yet.").font(.footnote).foregroundStyle(.secondary)
                Button("End trip") { confirmEnd = true }.buttonStyle(.borderedProminent)
            }
        }
        .onDisappear { location.endPreview() }
        .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("I've arrived") { store.finishTrip() }
            Button("Cancel trip", role: .destructive) { store.finishTrip(cancelled: true) }
        }
    }
}
