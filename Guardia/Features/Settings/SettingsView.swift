import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: GuardiaStore
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("routeCheckInsEnabled") private var reminders = true
    @AppStorage("deviationSensitivity") private var sensitivity = "balanced"
    @State private var confirmDelete = false
    @State private var confirmLinks = false
    @State private var notificationNotice: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $profileName).textContentType(.givenName).textInputAutocapitalization(.words)
                } header: { Text("Profile") } footer: { Text("Optional. Used for your greeting.") }
                Section {
                    Toggle("Check-in notifications", isOn: $reminders)
                    Picker("Route alerts", selection: $sensitivity) {
                        ForEach(DeviationSensitivity.allCases, id: \.rawValue) { value in
                            Text(value.rawValue.capitalized).tag(value.rawValue)
                        }
                    }
                    Button("Enable notifications") {
                        Task {
                            do {
                                notificationNotice = try await store.notifications.requestPermission()
                                    ? "Notifications are on." : "Notifications are off in your device settings."
                            } catch { notificationNotice = "Notifications aren’t available right now." }
                        }
                    }
                    if let notificationNotice { Text(notificationNotice).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Trip preferences") } footer: { Text("Balanced alerts suit most trips. Choose Attentive for earlier prompts or Relaxed for fewer prompts.") }
                Section("Destination arrival alerts") {
                    Text("Allow Always location access and notifications to receive an arrival reminder while Guardia is in the background. You still need to confirm arrival and end the trip.")
                        .font(.footnote)
                    Button("Open device settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Section("Privacy & security") {
                    Label("Protected with Face ID or passcode", systemImage: "lock.shield")
                    Button("Lock Guardia") { store.lock() }
                    NavigationLink("Your privacy") { GuardiaPrivacyView() }
                }
                Section {
                    Button("Remove shared links", role: .destructive) { confirmLinks = true }.disabled(store.isAuthenticating || store.sharing.busy)
                    Button("Clear trip history", role: .destructive) { confirmDelete = true }.disabled(store.isAuthenticating)
                } header: { Text("Manage your data") } footer: { Text("Your current trip and trusted contacts are kept.") }
                Section { LabeledContent("Guardia", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") }
            }.guardiaSurface().navigationTitle("Settings")
                .confirmationDialog("Remove all shared trip links?", isPresented: $confirmLinks, titleVisibility: .visible) {
                    Button("Remove links", role: .destructive) { Task { await store.deleteCloudData() } }
                } message: { Text("People with these links will lose access. You’ll need to be online to remove them.") }
                .confirmationDialog("Clear your trip history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Clear history", role: .destructive) { Task { await store.deleteHistory() } }
                } message: { Text("Finished trips and their routes will be permanently removed from this device.") }
        }
    }
}

private struct GuardiaPrivacyView: View {
    var body: some View {
        Form {
            Section("On your device") {
                Text("Your trips and trusted contacts are saved on this device. Guardia locks when you leave the app.")
            }
            Section("When you share a trip") {
                Text("Your destination, route, latest location, agreed fare and help status are available to anyone with your link. Stop sharing to remove access.")
            }
            Section("Messages to contacts") {
                Text("You choose whether to send a help message. Review it and tap Send. Guardia does not contact emergency services.")
            }
            Section("Maps & routes") {
                Text("Place search uses Apple Maps. Your start and destination are sent to the route provider to plan your journey. Travel times do not include live traffic.")
                Text("Route data © OpenStreetMap contributors. Routing by OSRM.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Fare estimates") {
                Text("Current estimates use generated prices. They are illustrative and may differ from actual fares. Agree your price with the driver.")
            }
        }.guardiaSurface().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
