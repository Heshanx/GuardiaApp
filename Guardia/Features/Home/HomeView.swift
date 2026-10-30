import SwiftUI

struct HomeView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("profileName") private var profileName = ""
    @State private var showPlan = false
    @State private var endedTrip: TripRecord?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let trip = store.activeTrip { ActiveTripView(store: store, trip: trip) }
                    else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(greeting).font(.largeTitle.bold())
                            Text("Heading somewhere?").font(.title3).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 24) {
                            Button { showPlan = true } label: {
                                VStack(spacing: 14) {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 38, weight: .medium))
                                    Text("Start Trip").font(.title2.bold())
                                }.foregroundStyle(.white).frame(width: 224, height: 224)
                                    .background(GuardiaStyle.buttonBlue, in: Circle())
                            }.buttonStyle(.plain).accessibilityHint("Choose a destination and preview your route")
                            if let last = store.trips.first(where: { $0.status != .active }) {
                                Label("Last trip to \(last.destination) \(last.status == .completed ? "completed" : "cancelled")", systemImage: "checkmark.circle")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, sizeClass == .regular ? 64 : 48)
                    }
                    NavigationLink { ContactsView(store: store) } label: {
                        HStack { Label("Trusted Contacts", systemImage: "person.2"); Spacer(); Text("\(store.contacts.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption) }
                            .font(.headline).padding(.vertical, 20)
                    }.buttonStyle(.plain)
                }.padding(24).frame(maxWidth: store.activeTrip == nil ? 760 : 1200).frame(maxWidth: .infinity)
            }.background(GuardiaStyle.background).navigationTitle(store.activeTrip == nil ? "" : "Your trip").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPlan) { TripPlanView(store: store).presentationDetents([.large]).presentationDragIndicator(.visible) }
                .sheet(item: $endedTrip) { TripCompletionView(trip: $0) }
                .onChange(of: store.activeTrip?.id) { old, new in
                    if let old, new == nil { endedTrip = store.trips.first { $0.id == old } }
                }
        }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : "\(base), \(name)"
    }
}
