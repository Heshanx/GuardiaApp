import SwiftUI

struct LiveSharingPanel: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var sharing: LiveSharingService
    @State private var confirm = false
    init(store: GuardiaStore) { self.store = store; sharing = store.sharing }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trusted contact live sharing").font(.headline)
            Text(sharing.status).font(.footnote).foregroundStyle(.secondary)
            if sharing.isEnabled {
                if let url = sharing.sharingURL { ShareLink("Share live trip link", item: url) }
                Button("Stop sharing") { Task { await sharing.stop() } }
                Text("Send this link to your contact. Anyone with it can view your latest location, planned route, destination, fare and alert state until revoked or expired. No push or SMS is sent.").font(.caption)
            } else { Button("Enable live sharing") { confirm = true }.disabled(sharing.busy) }
        }.confirmationDialog("Share this live trip through Firebase?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Enable live sharing") { if let trip = store.activeTrip { Task { await sharing.enable(for: trip) } } }
        } message: { Text("Uploads destination, planned route, latest GPS location, agreed fare and alert state to guardia-a63bd. You choose who receives the link. No automatic SMS or push delivery.") }
    }
}
