import SwiftUI

struct GuardiaRootView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isUnlocked {
                TabView {
                    HomeView(store: store).tabItem { Label("Home", systemImage: "house") }
                    TripHistoryView(store: store).tabItem { Label("Trips", systemImage: "clock") }
                    ContactsView(store: store).tabItem { Label("Contacts", systemImage: "person.2") }
                    SettingsView(store: store).tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 52)
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 88, weight: .light)).foregroundStyle(GuardiaStyle.accent)
                            .padding(28).background(GuardiaStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 40))
                            .accessibilityHidden(true)
                        VStack(spacing: 10) {
                            Text("Guardia").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("Your journey. Your peace of mind.").font(.title3).multilineTextAlignment(.center)
                            Text("A private place for your trips and the people you trust.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Button { Task { await store.unlock() } } label: {
                            HStack(spacing: 12) {
                                if store.isAuthenticating { ProgressView() } else { Image(systemName: "faceid") }
                                Text(store.isAuthenticating ? "Confirming it’s you…" : "Unlock Guardia").fontWeight(.semibold)
                            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isAuthenticating)
                        Label("Protected by Face ID or your device passcode", systemImage: "lock.shield")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
                }.background(GuardiaStyle.background)
            }
        }
        .tint(GuardiaStyle.accent)
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea().overlay { Label("Guardia", systemImage: "lock.shield") }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { store.lock() } }
        .alert("Guardia", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}
