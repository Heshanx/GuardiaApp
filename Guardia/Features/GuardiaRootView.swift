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
                VStack(spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 64)).foregroundStyle(GuardiaStyle.accent).accessibilityHidden(true)
                    Text("Guardia").font(.largeTitle.bold())
                    Text("Calm support for every street ride.").foregroundStyle(.secondary)
                    Button { Task { await store.unlock() } } label: {
                        HStack { if store.isAuthenticating { ProgressView() }; Text("Unlock Guardia") }
                            .frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.borderedProminent).disabled(store.isAuthenticating)
                    Text("Use Face ID or your device passcode to open your private trips and contacts.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(32)
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
