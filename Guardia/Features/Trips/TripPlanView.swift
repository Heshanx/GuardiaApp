import SwiftUI
import MapKit

struct TripPlanView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    @StateObject private var planner = RoutePlanner()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination = ""
    @State private var fare = ""
    @State private var confirmCheckInOnly = false

    init(store: GuardiaStore) { self.store = store; self.location = store.location }
    private var parsedFare: Double? { FareValidation.parse(fare, decimalSeparator: Locale.current.decimalSeparator ?? ".") }
    private var valid: Bool {
        planner.route != nil && location.freshSample != nil && (fare.isEmpty || parsedFare != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Current location") {
                    Label(location.status, systemImage: "location")
                    if location.needsSettings { Button("Open Settings") { openSettings() } }
                    else if location.freshSample == nil { Button("Find my location") { location.beginPreview() } }
                }
                Section("Where to?") {
                    TextField("Town, address or landmark", text: $destination)
                        .textInputAutocapitalization(.words).accessibilityIdentifier("tripDestination")
                        .onChange(of: destination) { _, _ in planner.clear() }
                        .onSubmit { search() }
                    Button("Search places") { search() }.disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || planner.isBusy)
                    ForEach(Array(planner.results.enumerated()), id: \.offset) { _, item in
                        Button {
                            guard let sample = location.freshSample else { return }
                            Task { await planner.plan(to: item, from: sample) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Place")
                                Text(item.address?.fullAddress ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(location.freshSample == nil || planner.isBusy)
                    }
                    if planner.isBusy { ProgressView("Finding your route…") }
                    if let error = planner.error { Text(error).foregroundStyle(.secondary) }
                }
                if let route = planner.route {
                    Section(planner.destinationName ?? "Route preview") {
                        TripRouteMap(route: route)
                        LabeledContent("Driving distance", value: Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                        LabeledContent("Estimated journey", value: "\(max(1, Int(route.expectedTravelTime / 60))) min")
                        Text("The blue line is the expected road route. Search again if you change your destination.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack { Text("LKR").foregroundStyle(.secondary); TextField("Agreed fare (optional)", text: $fare).keyboardType(.decimalPad) }
                } header: { Text("Agreed fare") } footer: { Text("Community fare comparisons are not connected yet.") }
                Section {
                    Label("Verified check-in", systemImage: "faceid")
                    Text("Confirm with Face ID or your device passcode. Your route records only during this trip, including when the screen is locked.").foregroundStyle(.secondary)
                    Button {
                        guard let route = planner.route, let name = planner.destinationName else { return }
                        Task { if await store.startTrip(destination: name, fare: parsedFare, route: route) { dismiss() } }
                    } label: { HStack { if store.isAuthenticating { ProgressView() }; Text("Confirm & Start") } }
                        .disabled(!valid || store.isAuthenticating || planner.isBusy)
                    if planner.route == nil {
                        Button("Start a check-in only") { confirmCheckInOnly = true }
                            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      (!fare.isEmpty && parsedFare == nil) || store.isAuthenticating || planner.isBusy)
                        Text("If a route is unavailable, you can still save your destination, fare and trip times locally.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.scrollDismissesKeyboard(.interactively).navigationTitle("New Trip").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isAuthenticating) } }
        }
        .confirmationDialog("Start without a route?", isPresented: $confirmCheckInOnly, titleVisibility: .visible) {
            Button("Start check-in only") {
                Task { if await store.startTrip(destination: destination, fare: parsedFare) { dismiss() } }
            }
        } message: { Text("This trip will save check-in details only. No locations will be recorded and no route checks or contact alerts will run.") }
        .interactiveDismissDisabled(store.isAuthenticating)
        .task { location.beginPreview() }
        .onDisappear { planner.clear(); location.endPreview() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { location.beginPreview() } }
    }
    private func search() { Task { await planner.searchPlaces(destination, from: location.freshSample) } }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
