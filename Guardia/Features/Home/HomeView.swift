import SwiftUI

struct HomeView: View {
    @ObservedObject var store: GuardiaStore
    @State private var showPlan = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Calm support for every street ride.").font(.subheadline).foregroundStyle(.secondary)
                    if let trip = store.activeTrip {
                        ActiveTripView(store: store, trip: trip)
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
        }
    }
}
