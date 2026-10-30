import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: GuardiaStore
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Face ID & Security") {
                    Label("Device authentication enabled", systemImage: "faceid")
                    Text("Guardia locks when it moves to the background. A new check-in requires authentication.").font(.footnote).foregroundStyle(.secondary)
                    Button("Lock Guardia") { store.lock() }
                }
                Section("Data & Privacy") {
                    Text("Your trip details and trusted contacts are stored locally on this iPhone. Destination search and driving routes use Apple Maps over the internet. Recorded trip locations stay on this device and are not shared with contacts.")
                }
                Section("Route check-in notifications") {
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
                Section("Coming next") {
                    Label("Community fare references", systemImage: "banknote")
                    Label("Trusted contact alerts", systemImage: "bell")
                }
                Section { LabeledContent("Guardia", value: "0.2 · Local check-in") }
            }.navigationTitle("Settings")
        }
    }
}
