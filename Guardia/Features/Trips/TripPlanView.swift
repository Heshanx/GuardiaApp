import SwiftUI
import MapKit

struct TripPlanView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var location: TripLocationService
    @StateObject private var planner = RoutePlanner()
    @StateObject private var fareReferences = FareReferenceService()
    @State private var fareArea = ""
    @StateObject private var connection = ConnectionStatus()
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
                Section("Where to?") {
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
                    if let selectedPlace, planner.route == nil, !planner.isBusy {
                        Label("Selected: \(selectedPlace.name ?? "Destination")", systemImage: "checkmark.circle.fill")
                        if location.freshSample == nil { Text("Your destination is selected. Wait for a location fix, then preview the route.").font(.footnote).foregroundStyle(.secondary) }
                        Button("Preview route") {
                            guard let sample = location.freshSample else { location.beginPreview(); return }
                            Task { await planner.plan(to: selectedPlace, from: sample) }
                        }
                    }
                    if planner.isBusy { ProgressView("Finding your route…") }
                    if let error = planner.error { Text(error).foregroundStyle(.secondary) }
                }
                if let selectedPlace {
                    Section {
                        Label(selectedPlace.name ?? "Destination", systemImage: "mappin.circle.fill").font(.headline)
                        Button("Choose another destination") { self.selectedPlace = nil; planner.clear(); editingDestination = true }
                    }
                }
                if let route = planner.route {
                    Section("Your route") {
                        Text(planner.destinationName ?? "Destination").font(.headline)
                        if !editingDestination && !editingFare { TripRouteMap(route: route) }
                        else { Label("Route preview pauses while you type", systemImage: "map").font(.footnote).foregroundStyle(.secondary) }
                        Button("Refresh route from my location") {
                            if let selectedPlace, let sample = location.freshSample { Task { await planner.plan(to: selectedPlace, from: sample) } }
                            else { location.beginPreview() }
                        }.disabled(planner.isBusy)
                        LabeledContent("Driving distance", value: Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                        LabeledContent("Estimated journey", value: "\(max(1, Int(route.expectedTravelTime / 60))) min")
                        Text("OSRM · © OpenStreetMap contributors. Start and destination are sent to the routing service. Estimated time excludes live traffic.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack { Text("LKR").foregroundStyle(.secondary); TextField("Agreed fare (optional)", text: $fare).keyboardType(.decimalPad).textFieldStyle(.plain).frame(minHeight: 44).focused($editingFare) }
                } header: { Text("Agreed fare") } footer: { Text("Optional. Comparisons are informational, not a guaranteed price.") }
                Section("Fare reference · Tuk-tuk") {
                    Picker("Area", selection: $fareArea) {
                        Text("Select area").tag("")
                        Text("Colombo").tag("colombo")
                        Text("Kandy").tag("kandy")
                        Text("Galle").tag("galle")
                    }
                    if fareReferences.loading { ProgressView("Loading fare reports…") }
                    if let reference = fareReferences.reference {
                        if let quote = parsedFare { Text(reference.assessment(for: quote)).font(.headline).foregroundStyle(GuardiaStyle.accent) }
                        LabeledContent("Reported range", value: "LKR \(reference.lower.formatted())–\(reference.upper.formatted())")
                        LabeledContent("Median", value: reference.median.formatted(.currency(code: "LKR")))
                    }
                    Text(fareReferences.status).font(.footnote).foregroundStyle(.secondary)
                    Text("Lookup uses only this selected area and a 5 km distance band. No exact coordinates are sent to Firestore.").font(.caption).foregroundStyle(.secondary)
                    Button("Refresh fare reference") { Task { await fareReferences.load(area: fareArea, distance: planner.route?.distance) } }.disabled(fareReferences.loading)
                }
                Section("Location & connection") {
                    DisclosureGroup("Connection details") {
                    Label(connection.summary, systemImage: "network")
                    Text("A connection being available does not guarantee the road routing service is reachable.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Guardia settings") { openSettings() }
                }
                    DisclosureGroup("Starting location") {
                    Label("Start: your current GPS location", systemImage: "location.fill").font(.headline)
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        if let sample = location.freshSample {
                            Text("\(sample.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(sample.coordinate.longitude.formatted(.number.precision(.fractionLength(5)))) · ±\(Int(sample.accuracy)) m")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else { Text(location.status == "Location ready" ? "Waiting for a fresh GPS fix…" : location.status).font(.subheadline) }
                    }
                    if let sample = location.latest, !editingDestination && !editingFare {
                        Map(initialPosition: .region(MKCoordinateRegion(center: sample.coordinate.mapCoordinate, latitudinalMeters: 600, longitudinalMeters: 600))) {
                            Marker("Current starting point", coordinate: sample.coordinate.mapCoordinate)
                        }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button("Refresh starting location") { location.beginPreview() }
                    Text("The route starts at your phone’s GPS position. You only need to select a destination.").font(.footnote).foregroundStyle(.secondary)
                    if location.needsSettings { Button("Open Settings") { openSettings() } }
                    else if location.freshSample == nil { Button(location.hasPermission ? "Find my location" : "Allow location access") { location.beginPreview() } }
                }
                }
                Section {
                    Label("Verified check-in", systemImage: "faceid")
                    Text("Confirm with Face ID or your device passcode. Your route records only during this trip, including when the screen is locked.").foregroundStyle(.secondary)
                    if planner.route == nil {
                        Button("Start a check-in only") { confirmCheckInOnly = true }
                            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      (!fare.isEmpty && parsedFare == nil) || store.isAuthenticating || planner.isBusy)
                        Text("If a route is unavailable, you can still save your destination, fare and trip times locally.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.scrollDismissesKeyboard(.interactively).navigationTitle("Where to?").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isAuthenticating) } }
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
                        HStack { if store.isAuthenticating { ProgressView() }; Text(store.isAuthenticating ? "Confirming…" : (planner.route == nil ? "Start check-in only" : "Start my trip")).fontWeight(.semibold); Image(systemName: "arrow.right") }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(!valid || store.isAuthenticating || planner.isBusy)
                }
            }.padding().background(.regularMaterial)
        }
        .confirmationDialog("Start without a route?", isPresented: $confirmCheckInOnly, titleVisibility: .visible) {
            Button("Start check-in only") {
                Task { if await store.startTrip(destination: selectedPlace?.name ?? destination, fare: parsedFare) { dismiss() } }
            }
        } message: { Text("This trip will save check-in details only. No locations will be recorded and no route checks or contact alerts will run.") }
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
        if planner.route == nil { return "No planned route. Check-in only saves trip details; route monitoring will be off." }
        if location.freshSample == nil { return "Refresh your starting location to get a recent GPS fix." }
        if !fare.isEmpty && parsedFare == nil { return "Enter a valid fare or leave it empty." }
        if let route = planner.route, let sample = location.freshSample, !route.canStart(from: sample, now: Date()) {
            return "Your route preview is old or the starting point changed. Refresh the route."
        }
        return "Route ready. Confirm with Face ID or your passcode."
    }
    private func search() { Task { await planner.searchPlaces(destination, from: location.freshSample) } }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
