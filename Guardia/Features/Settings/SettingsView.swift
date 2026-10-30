import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: GuardiaStore
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("routeCheckInsEnabled") private var routeCheckInsEnabled = true
    @State private var confirmDelete = false
    @State private var confirmCloudDelete = false
    @AppStorage("trackerBaseURL") private var trackerBaseURL = "https://guardia-a63bd.web.app/track.html"
    @State private var notice: String?
    @AppStorage("deviationSensitivity") private var sensitivity = "balanced"
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Your name (optional)", text: $profileName).textContentType(.givenName).textInputAutocapitalization(.words)
                    Text("Used only for your greeting on this device.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Face ID & Security") {
                    Label("Device authentication enabled", systemImage: "faceid")
                    Text("Guardia locks when it moves to the background. A new check-in requires authentication.").font(.footnote).foregroundStyle(.secondary)
                    Button("Lock Guardia") { store.lock() }
                }
                Section("Data & Privacy") {
                    Text("Your trip details and trusted contacts are stored locally on this iPhone. Destination search uses Apple Maps. Driving routes use the public OSRM service and OpenStreetMap data; start and destination coordinates are sent to that service over the internet. Recorded traces stay on this device. If you enable live sharing, your latest position, planned route, destination, agreed fare and alert state are uploaded to Firebase for the browser sharing link.")
                }
                Section("Route check-in notifications") {
                    Toggle("Route check-ins", isOn: $routeCheckInsEnabled)
                    Button("Allow quiet notifications") {
                        Task {
                            do {
                                let allowed = try await store.notifications.requestPermission()
                                notice = allowed ? "Notifications are allowed." : "Notifications are off. Enable them in iPhone Settings."
                            } catch { notice = error.localizedDescription }
                        }
                    }
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("Notifications contain no trip details or sound. Delivery depends on iPhone notification and Focus settings.").font(.footnote)
                    if let notice { Text(notice).font(.footnote) }
                }
                Section("Route sensitivity") {
                    Picker("Deviation tolerance", selection: $sensitivity) {
                        ForEach(DeviationSensitivity.allCases, id: \.rawValue) { level in
                            Text("\(level.rawValue.capitalized) · \(Int(level.meters)) m").tag(level.rawValue)
                        }
                    }
                    Text("Balanced is recommended. A check-in requires a sustained departure; reported GPS uncertainty is accounted for before applying this tolerance.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Local testing · Live sharing") {
                    TextField("Tracker page URL", text: $trackerBaseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use the Firebase Hosting tracker URL, or your Mac’s LAN URL. The tracker page must be deployed or served before links will open.").font(.footnote)
                    Text(store.sharing.status).font(.footnote)
                }
                Section("Delete data") {
                    Button("Delete cloud sharing data", role: .destructive) { confirmCloudDelete = true }.disabled(store.isAuthenticating)
                    Text("Deletes live-sharing records for this device’s Firebase identity. Public aggregate fare data is kept.").font(.footnote)
                    Button("Delete previous trip history", role: .destructive) { confirmDelete = true }.disabled(store.isAuthenticating)
                    Text("Requires fresh device authentication. Keeps the current trip and your contacts.").font(.footnote)
                }
                Section("Coming next") {
                    Label("Community fare references", systemImage: "banknote")
                    Label("Trusted contact alerts", systemImage: "bell")
                }
                Section { LabeledContent("Guardia", value: "0.2 · Local check-in") }
            }.navigationTitle("Settings").confirmationDialog("Delete your cloud sharing data?", isPresented: $confirmCloudDelete, titleVisibility: .visible) {
                Button("Delete cloud data", role: .destructive) { Task { await store.deleteCloudData() } }
            } message: { Text("Requires fresh device authentication and network access. Revokes sharing links. Offline failures will be reported.") }.confirmationDialog("Delete previous local trips?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete history", role: .destructive) { Task { await store.deleteHistory() } }
            } message: { Text("This permanently deletes finished/cancelled trips and their recorded routes from this device.") }
        }
    }
}
