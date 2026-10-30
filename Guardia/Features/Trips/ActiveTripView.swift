import SwiftUI
import CoreLocation

struct ActiveTripView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    let trip: TripRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmEnd = false
    @State private var fullMap = false
    @State private var confirmAlert = false
    init(store: GuardiaStore, trip: TripRecord) { self.store = store; self.location = store.location }
    var body: some View {
        Group {
            if trip.route != nil {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 20) { mapPanel; tripPanel }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            mapPanel.frame(minWidth: 400)
                            tripPanel.frame(minWidth: 300, maxWidth: 420)
                        }
                        VStack(spacing: 20) { mapPanel; tripPanel }
                    }
                }
            } else { tripPanel }
        }
        .fullScreenCover(isPresented: $fullMap) { FullTripMapView(store: store) }
        .confirmationDialog("Request a check-in?", isPresented: $confirmAlert, titleVisibility: .visible) {
            Button("Continue") { store.manualCheckIn() }
        } message: { Text("You’ll be asked how you’re doing. You can choose to message a contact if you need help.") }
        .sheet(item: Binding(get: { fullMap ? nil : trip.route?.checkIns?.first(where: { $0.response == nil }) }, set: { _ in })) { check in
            RouteCheckInSheet(store: store, check: check).presentationDetents([.large])
                .presentationDragIndicator(.visible).interactiveDismissDisabled().presentationSizing(.form)
        }
        .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("I’ve arrived") { store.finishTrip() }
            Button("Cancel trip", role: .destructive) { store.finishTrip(cancelled: true) }
        }
        .onDisappear { location.endPreview() }
    }
    @ViewBuilder private var mapPanel: some View {
        if let route = trip.route {
            VStack(alignment: .leading, spacing: 12) {
                TripRouteMap(route: route, showsUser: location.isRecording, height: 360)
                Button { fullMap = true } label: { Label("View map", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .frame(minHeight: 44)
            }
        }
    }
    private var tripPanel: some View {
        GuardiaCard {
            Label(location.isRecording ? "On your way" : "Your journey", systemImage: "location.circle.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(GuardiaStyle.accent)
            Text(trip.destination).font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(trip.startedAt, style: .timer).font(.title2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let fare = trip.agreedFare { LabeledContent("Agreed fare", value: fare.formatted(.currency(code: "LKR").precision(.fractionLength(0)))) }
            if let route = trip.route {
                LabeledContent("Travel time", value: "\(max(1, Int(route.expectedTravelTime / 60))) min")
                if !location.isRecording {
                    Text("Location updates are paused.").font(.footnote).foregroundStyle(.secondary)
                    if location.authorization == .notDetermined {
                        Button("Use my location") { location.beginPreview() }
                    } else if location.needsSettings {
                        Button("Allow location") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else { Button("Resume journey") { store.resumeRecording() }.disabled(!location.hasPermission) }
                } else {
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        if location.freshSample == nil { Label("Waiting for your location", systemImage: "location.slash").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Divider()
                LiveSharingPanel(store: store)
            } else { Text("Saved without a route. Location alerts and sharing are off.").font(.footnote).foregroundStyle(.secondary) }
            Divider()
            if trip.route != nil {
                Button { confirmAlert = true } label: { Label("Request a check-in", systemImage: "checkmark.shield") }.frame(minHeight: 44)
            }
            Button("End trip") { confirmEnd = true }.buttonStyle(GuardiaPrimaryButton())
        }
    }
}
