import SwiftUI

@MainActor
struct GuardiaRootView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isUnlocked {
                TabView {
                    dashboard.tabItem { Label("Trip", systemImage: "location.circle") }
                    history.tabItem { Label("History", systemImage: "clock") }
                    NavigationStack {
                        ContentUnavailableView("No trusted contacts yet", systemImage: "person.2",
                                               description: Text("Contact management and invitations are planned. No alerts can be sent from this starter."))
                            .navigationTitle("Trusted Contacts")
                    }.tabItem { Label("Contacts", systemImage: "person.2") }
                    NavigationStack {
                        Form {
                            Section("Privacy") {
                                Text("Practice trips stay on this device. Device authentication unlocks local data; no online account is connected.")
                                Button("Lock Guardia") { store.lock() }
                            }
                            Section("Development status") {
                                Text("Live location, route alerts, fare references and notification preferences are not connected yet.")
                            }
                        }.navigationTitle("Settings")
                    }.tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled").font(.largeTitle).accessibilityHidden(true)
                    Text("Guardia").font(.largeTitle.bold())
                    Text("Your private trip journal").font(.headline)
                    Button("Unlock Guardia") { Task { await store.unlock() } }
                        .buttonStyle(.borderedProminent).disabled(store.isAuthenticating)
                    Text("Use Face ID, Touch ID or your device passcode.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
        }
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                    .overlay { Label("Guardia", systemImage: "lock.shield") }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Do not lock for the temporary inactive phase of a biometric prompt.
            if phase == .background { store.lock() }
        }
        .alert("Guardia", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private var dashboard: some View {
        NavigationStack {
            List {
                Section {
                    Label("Practice mode", systemImage: "hammer")
                    Text("This starter records start and finish times only. It does not monitor your route or notify anyone.")
                        .foregroundStyle(.secondary)
                }
                Section("Your trip") {
                    if let trip = store.activeTrip {
                        Text("Practice trip in progress").font(.headline)
                        Text(trip.startedAt, format: .dateTime)
                        Button("Finish practice trip") { store.finishTrip() }
                        Button("Cancel practice trip", role: .destructive) { store.finishTrip(cancelled: true) }
                    } else {
                        Button { store.startPracticeTrip() } label: { Label("Start practice trip", systemImage: "play.fill") }
                    }
                }
                if let last = store.trips.first(where: { $0.status != .active }) {
                    Section("Last trip") { tripRow(last) }
                }
            }.navigationTitle("Guardia")
        }
    }

    private var history: some View {
        NavigationStack {
            List(store.trips) { trip in tripRow(trip) }
                .overlay {
                    if store.trips.isEmpty {
                        ContentUnavailableView("No trips yet", systemImage: "clock",
                                               description: Text("Your practice trips will appear here."))
                    }
                }
                .navigationTitle("Trip History")
        }
    }

    private func tripRow(_ trip: TripRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.status.rawValue.capitalized).font(.headline)
            Text(trip.startedAt, format: .dateTime).font(.subheadline)
            if let end = trip.endedAt { Text("Ended \(end.formatted())").font(.caption) }
        }
    }
}
