import SwiftUI

struct HomeView: View {
    @ObservedObject var store: GuardiaStore
    @State private var showPlan = false
    @State private var confirmEnd = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Calm support for every street ride.").font(.subheadline).foregroundStyle(.secondary)
                    if let trip = store.activeTrip {
                        GuardiaCard {
                            Label("Trip in progress", systemImage: "location.circle.fill").font(.headline)
                            Text(trip.destination).font(.largeTitle.bold())
                            Text("Started \(trip.startedAt.formatted(date: .omitted, time: .shortened))")
                            TimelineView(.periodic(from: .now, by: 1)) { _ in Text(trip.startedAt, style: .timer).font(.title.monospacedDigit()) }
                            if let fare = trip.agreedFare { Text(fare, format: .currency(code: "LKR")) }
                            Text("Recording trip details on this device. Route monitoring and contact alerts are not connected yet.").font(.footnote).foregroundStyle(.secondary)
                            Button("End trip") { confirmEnd = true }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        GuardiaCard {
                            Image(systemName: "location.north.circle").font(.system(size: 44)).foregroundStyle(GuardiaStyle.accent)
                            Text("Heading somewhere?").font(.largeTitle.bold())
                            Text("Save your destination and agreed fare, then check in securely.").foregroundStyle(.secondary)
                            Button { showPlan = true } label: { Label("Start Trip", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(10) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if let last = store.trips.first(where: { $0.status != .active }) {
                        GuardiaCard {
                            Label("Last trip", systemImage: "clock")
                            Text(last.destination).font(.headline)
                            Text(last.status == .completed ? "Trip completed" : "Trip cancelled").foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { ContactsView(store: store) } label: {
                        GuardiaCard { Label("Trusted Contacts", systemImage: "person.2"); Text("\(store.contacts.count) of 3 contacts added").font(.subheadline).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                }.padding(20)
            }.background(GuardiaStyle.background).navigationTitle("Guardia")
                .sheet(isPresented: $showPlan) { TripPlanView(store: store) }
                .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
                    Button("I've arrived") { store.finishTrip() }
                    Button("Cancel trip", role: .destructive) { store.finishTrip(cancelled: true) }
                }
        }
    }
}
