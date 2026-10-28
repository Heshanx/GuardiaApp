import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: GuardiaStore
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
                Section("Coming next") {
                    Label("Route deviation watch", systemImage: "map")
                    Label("Community fare references", systemImage: "banknote")
                    Label("Trusted contact alerts", systemImage: "bell")
                }
                Section { LabeledContent("Guardia", value: "0.2 · Local check-in") }
            }.navigationTitle("Settings")
        }
    }
}
