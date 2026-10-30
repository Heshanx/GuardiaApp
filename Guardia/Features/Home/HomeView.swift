import SwiftUI

struct HomeView: View {
    @ObservedObject var store: GuardiaStore
    @AppStorage("profileName") private var profileName = ""
    @ObservedObject private var launchRequest = GuardiaLaunchRequest.shared
    @State private var showPlan = false
    @State private var endedTrip: TripRecord?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let trip = store.activeTrip {
                        ActiveTripView(store: store, trip: trip)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(greeting).font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("A little peace of mind, wherever you go.").font(.title3).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 24) {
                                startCard.frame(minWidth: 340)
                                peopleCard.frame(minWidth: 280)
                            }
                            VStack(spacing: 20) { startCard; peopleCard }
                        }
                        if let last = store.trips.first(where: { $0.status != .active }) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Last journey").font(.headline)
                                NavigationLink {
                                    TripHistoryView(store: store)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(GuardiaStyle.accent)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(last.destination).font(.headline).foregroundStyle(.primary)
                                            Text(last.startedAt, format: .dateTime.day().month()).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }.background(GuardiaStyle.background)
                .navigationTitle(store.activeTrip == nil ? "Guardia" : "Your trip")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPlan) {
                    TripPlanView(store: store).presentationDetents([.large]).presentationDragIndicator(.visible)
                        .presentationSizing(.form)
                }
                .sheet(item: $endedTrip) { TripCompletionView(store: store, trip: $0).presentationSizing(.form) }
                .task { consumeLaunchRequest() }
                .onChange(of: launchRequest.action) { _, _ in consumeLaunchRequest() }
                .onChange(of: store.activeTrip?.id) { old, new in
                    if let old, new == nil { endedTrip = store.trips.first { $0.id == old } }
                }
        }
    }
    private var startCard: some View {
        GuardiaCard {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 34, weight: .medium)).foregroundStyle(GuardiaStyle.accent).accessibilityHidden(true)
            Text("Where are you headed?").font(.system(.title2, design: .rounded, weight: .semibold))
            Text("Plan your route and share your journey with someone you trust.").foregroundStyle(.secondary)
            Button { showPlan = true } label: {
                HStack { Text("Start a trip").padding(.horizontal, 16); Spacer(); Image(systemName: "arrow.right").padding(.horizontal, 16) }
            }.buttonStyle(GuardiaPrimaryButton())
        }
    }
    private var peopleCard: some View {
        GuardiaCard {
            Image(systemName: "person.2").font(.system(size: 30, weight: .medium)).foregroundStyle(GuardiaStyle.accent).accessibilityHidden(true)
            Text("Your people").font(.system(.title2, design: .rounded, weight: .semibold))
            Text(store.contacts.isEmpty ? "Add someone you can turn to along the way." : store.contacts.map(\.name).joined(separator: ", "))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            NavigationLink { ContactsView(store: store) } label: {
                HStack { Text(store.contacts.isEmpty ? "Add trusted contacts" : "Manage contacts"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.headline).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(GuardiaStyle.accent)
        }
    }
    private func consumeLaunchRequest() {
        guard store.isUnlocked, let action = launchRequest.action else { return }
        launchRequest.action = nil
        switch action {
        case .dashboard: break
        case .plan: if store.activeTrip == nil { showPlan = true }
        case .checkIn:
            if store.activeTrip != nil { store.manualCheckIn() }
            else { store.message = "Start a trip before requesting a check-in." }
        }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : "\(base), \(name)"
    }
}
