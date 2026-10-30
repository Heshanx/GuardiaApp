import SwiftUI
import MapKit

struct TripPlanView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    @StateObject private var planner = RoutePlanner()
    @StateObject private var fareReferences = FareReferenceService()
    @State private var fareArea = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination = ""
    @State private var fare = ""
    @State private var confirmCheckInOnly = false
    @State private var selectedPlace: MKMapItem?
    @FocusState private var editingDestination: Bool
    @FocusState private var editingFare: Bool

    init(store: GuardiaStore) { self.store = store; self.location = store.location }
    private var parsedFare: Double? { FareValidation.parse(fare, decimalSeparator: Locale.current.decimalSeparator ?? ".") }
    private var valid: Bool {
        guard selectedPlace != nil, fare.isEmpty || parsedFare != nil else { return false }
        if let route = planner.route {
            guard let sample = location.freshSample else { return false }
            return route.canStart(from: sample, now: Date())
        }
        return true
    }
    var body: some View {
        NavigationStack {
            Form {
                if selectedPlace == nil {
                Section("Destination") {
                    TextField("Town, address or landmark", text: $destination)
                        .textInputAutocapitalization(.words).accessibilityIdentifier("tripDestination")
                        .textFieldStyle(.plain)
                        .frame(minHeight: 44)
                        .autocorrectionDisabled()
                        .focused($editingDestination)
                        .submitLabel(.search)
                        .onChange(of: destination) { _, _ in selectedPlace = nil; planner.clear() }
                        .onSubmit { search() }
                    Button("Search places") { search() }.disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || planner.isBusy)
                    ForEach(Array((selectedPlace == nil ? planner.results : []).enumerated()), id: \.offset) { _, item in
                        Button {
                            editingDestination = false
                            selectedPlace = item
                            if let sample = location.freshSample { Task { await planner.plan(to: item, from: sample) } }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Image(systemName: "mappin.circle.fill"); Text(item.name ?? "Place").font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                Text(item.address?.fullAddress ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(planner.isBusy)
                    }
                    if planner.isBusy { ProgressView("Finding your route…") }
                    if let error = planner.error { Text(error).foregroundStyle(.secondary) }
                }
                }
                if let selectedPlace {
                    Section("Destination") {
                        Label(selectedPlace.name ?? "Destination", systemImage: "mappin.circle.fill").font(.headline)
                        Button("Change destination") { self.selectedPlace = nil; planner.clear(); editingDestination = true }
                        if planner.isBusy { ProgressView("Preparing your route…") }
                        if let error = planner.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                        if planner.route == nil, !planner.isBusy {
                            Button("Preview route") {
                                guard let sample = location.freshSample else { location.beginPreview(); return }
                                Task { await planner.plan(to: selectedPlace, from: sample) }
                            }
                        }
                    }
                }
                if let route = planner.route {
                    Section("Your route") {
                        if !editingDestination && !editingFare { TripRouteMap(route: route) }
                        else { Label("Route preview pauses while you type", systemImage: "map").font(.footnote).foregroundStyle(.secondary) }
                        Button("Update route") {
                            if let selectedPlace, let sample = location.freshSample { Task { await planner.plan(to: selectedPlace, from: sample) } }
                            else { location.beginPreview() }
                        }.disabled(planner.isBusy)
                        LabeledContent("Distance", value: Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                        LabeledContent("Travel time", value: "\(max(1, Int(route.expectedTravelTime / 60))) min")
                        Text("Travel time excludes live traffic.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack { Text("LKR").foregroundStyle(.secondary); TextField("Amount (optional)", text: $fare).keyboardType(.decimalPad).textFieldStyle(.plain).frame(minHeight: 44).focused($editingFare) }
                } header: { Text("Agreed fare") } footer: { Text("Enter the price you agreed with your driver.") }
                if planner.route != nil {
                Section("Fare estimate") {
                    Picker("Area", selection: $fareArea) {
                        Text("Choose area").tag("")
                        Text("Colombo").tag("colombo")
                        Text("Kandy").tag("kandy")
                        Text("Galle").tag("galle")
                    }
                    if fareReferences.loading {
                        ProgressView("Preparing estimate…")
                    } else if let reference = fareReferences.reference {
                        FareEstimateView(reference: reference, quote: parsedFare)
                    } else {
                        Text(fareReferences.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Refresh") { Task { await fareReferences.load(area: fareArea, distance: planner.route?.distance) } }
                        .disabled(fareReferences.loading)
                }
                }
                if location.freshSample == nil {
                    Section("Starting point") {
                        Label(location.needsSettings ? "Location access is off" : "Finding your location…", systemImage: "location")
                        if location.needsSettings {
                            Button("Allow location") { openSettings() }
                        } else {
                            Button(location.hasPermission ? "Try again" : "Use my location") { location.beginPreview() }
                        }
                    }
                }
                Section {
                    if planner.route == nil {
                        Button("Continue without a route") { confirmCheckInOnly = true }
                            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      (!fare.isEmpty && parsedFare == nil) || store.isAuthenticating || planner.isBusy)
                        Text("You can still save your trip when a route is unavailable.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.guardiaSurface(width: 840).scrollDismissesKeyboard(.interactively).navigationTitle("Where to?").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isAuthenticating) } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(readiness).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        editingDestination = false; editingFare = false
                        guard let route = planner.route else { confirmCheckInOnly = true; return }
                        guard let name = planner.destinationName else { return }
                        Task { if await store.startTrip(destination: name, fare: parsedFare, route: route) { dismiss() } }
                    } label: {
                        HStack { if store.isAuthenticating { ProgressView() }; Text(store.isAuthenticating ? "Confirming…" : (planner.route == nil ? "Continue without a route" : "Start my trip")).fontWeight(.semibold); Image(systemName: "arrow.right") }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(!valid || store.isAuthenticating || planner.isBusy)
                }
            }.padding().frame(maxWidth: 840).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .confirmationDialog("Start without a route?", isPresented: $confirmCheckInOnly, titleVisibility: .visible) {
            Button("Continue without a route") {
                Task { if await store.startTrip(destination: selectedPlace?.name ?? destination, fare: parsedFare) { dismiss() } }
            }
        } message: { Text("Your destination and fare will be saved. Location recording, route alerts and live sharing will be off.") }
        .interactiveDismissDisabled(store.isAuthenticating)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingDestination = false; editingFare = false }
            }
        }
        .task { if location.hasPermission { location.beginPreview() } }
        .task(id: "\(fareArea)-\(planner.route?.distance ?? 0)") {
            await fareReferences.load(area: fareArea, distance: planner.route?.distance)
        }
        .task(id: destination) {
            guard selectedPlace == nil, destination.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, selectedPlace == nil else { return }
            await planner.searchPlaces(destination, from: location.freshSample)
        }
        .onChange(of: location.latest) { _, sample in
            guard let sample, sample.isUsable(at: Date()), let selectedPlace,
                  planner.route == nil, !planner.isBusy, planner.error == nil else { return }
            Task { await planner.plan(to: selectedPlace, from: sample) }
        }
        .onDisappear { planner.clear(); location.endPreview() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && location.hasPermission { location.beginPreview() } }
    }
    private var readiness: String {
        if planner.isBusy { return "Finding your route…" }
        if selectedPlace == nil { return "Choose a destination from the search results." }
        if planner.route == nil { return "A route is unavailable. You can save the trip without location alerts." }
        if location.freshSample == nil { return "Update your starting point to continue." }
        if !fare.isEmpty && parsedFare == nil { return "Enter a valid fare or leave it empty." }
        if let route = planner.route, let sample = location.freshSample, !route.canStart(from: sample, now: Date()) {
            return "Your starting point changed. Update the route to continue."
        }
        return "Ready when you are."
    }
    private func search() { Task { await planner.searchPlaces(destination, from: location.freshSample) } }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
