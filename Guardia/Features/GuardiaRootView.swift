import SwiftUI

struct GuardiaRootView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("completedIntroduction") private var completedIntroduction = false
    @State private var autoUnlockAttempted = false
    @ObservedObject private var launchRequest = GuardiaLaunchRequest.shared
    @State private var selectedTab = 0
    @State private var section: GuardiaSection? = .home

    var body: some View {
        Group {
            if store.isUnlocked {
                if !completedIntroduction {
                    IntroductionView(store: store)
                } else if sizeClass == .regular {
                    NavigationSplitView {
                        List(GuardiaSection.allCases, selection: $section) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }.navigationTitle("Guardia").navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
                    } detail: { sectionView(section ?? .home) }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    TabView(selection: $selectedTab) {
                        HomeView(store: store).tabItem { Label("Home", systemImage: "house") }.tag(0)
                        TripHistoryView(store: store).tabItem { Label("Trips", systemImage: "clock") }.tag(1)
                        ContactsView(store: store).tabItem { Label("Contacts", systemImage: "person.2") }.tag(2)
                        SettingsView(store: store).tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                    }
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
                            Text("Calm support for every street ride.").font(.title3).multilineTextAlignment(.center)
                            Text("A private place for your trips and the people you trust.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Button { Task { await store.unlock() } } label: {
                            HStack(spacing: 12) {
                                if store.isAuthenticating { ProgressView() } else { Image(systemName: "faceid") }
                                Text(store.isAuthenticating ? "Confirming it’s you…" : "Unlock Guardia").fontWeight(.semibold)
                            }.padding(.horizontal, 18).padding(.vertical, 5)
                        }.buttonStyle(.borderedProminent).controlSize(.regular).disabled(store.isAuthenticating)
                        Label("Protected by Face ID or your device passcode", systemImage: "lock.shield")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
                }.background(GuardiaStyle.background)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !store.isUnlocked, !autoUnlockAttempted else { return }
            autoUnlockAttempted = true
            await store.unlock()
        }
        .onChange(of: launchRequest.action) { _, action in
            if action != nil { selectedTab = 0; section = .home }
        }
        .tint(GuardiaStyle.accent)
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea().overlay { Label("Guardia", systemImage: "lock.shield") }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { autoUnlockAttempted = false; store.lock() } }
        .alert("Guardia", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
    @ViewBuilder private func sectionView(_ item: GuardiaSection) -> some View {
        switch item {
        case .home: HomeView(store: store)
        case .trips: TripHistoryView(store: store)
        case .contacts: ContactsView(store: store)
        case .settings: SettingsView(store: store)
        }
    }

}

private enum GuardiaSection: String, CaseIterable, Identifiable {
    case home, trips, contacts, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .home: return "house"; case .trips: return "clock"; case .contacts: return "person.2"; case .settings: return "gearshape" }
    }
}
