import SwiftUI

struct FullTripMapView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAlert = false
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let route = store.activeTrip?.route {
                    TripRouteMap(route: route, showsUser: store.location.isRecording, height: geometry.size.height)
                } else { ContentUnavailableView("Trip ended", systemImage: "checkmark.circle") }
            }.navigationTitle("Live trip").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) { Button("Raise manual check-in") { confirmAlert = true }.disabled(store.activeTrip == nil) }
            }
        }
        .confirmationDialog("Raise a manual check-in?", isPresented: $confirmAlert, titleVisibility: .visible) {
            Button("Raise check-in") { store.manualCheckIn() }
        }
        .sheet(item: Binding(get: { store.activeTrip?.route?.checkIns?.first(where: { $0.response == nil }) }, set: { _ in })) { check in
            RouteCheckInSheet(store: store, check: check).presentationDetents([.medium, .large]).interactiveDismissDisabled()
        }
    }
}
