import SwiftUI
import UIKit

struct LiveSharingPanel: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var sharing: LiveSharingService
    @ObservedObject private var location: TripLocationService
    @State private var confirm = false
    init(store: GuardiaStore) { self.store = store; sharing = store.sharing; location = store.location }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Share your journey", systemImage: "person.2.wave.2").font(.headline)
            if let notice = sharing.userNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if sharing.busy { ProgressView("Please wait…") }
            if sharing.isEnabled, let url = sharing.sharingURL {
                ShareLink(item: url, subject: Text("My Guardia trip"), message: Text("Follow my trip with Guardia.")) {
                    Label("Share trip", systemImage: "square.and.arrow.up")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if let fix = store.activeTrip?.route?.samples.last,
                       context.date.timeIntervalSince(fix.timestamp) > 60 {
                        Label("Location hasn’t updated recently", systemImage: "location.slash").font(.footnote).foregroundStyle(.orange)
                    }
                }
                Text("Anyone with your link can follow this trip until you stop sharing or the link expires.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let expiry = sharing.expiresAt {
                    Text("Available until \(expiry.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Stop sharing", role: .destructive) { Task { await sharing.stop() } }.disabled(sharing.busy)
            } else if !sharing.busy, store.activeTrip?.route != nil {
                Button("Share trip") { confirm = true }.buttonStyle(.bordered).controlSize(.large).disabled(!location.hasPermission)
                Text(location.hasPermission ? "Let someone you trust follow your journey." : "Allow location access to share your journey.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if sharing.busy {
                Button("Cancel") { Task { await sharing.stop() } }
            }
        }
        .confirmationDialog("Share your journey?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Create sharing link") {
                if let trip = store.activeTrip {
                    if !location.isRecording { store.resumeRecording() }
                    Task { await sharing.enable(for: store.activeTrip ?? trip) }
                }
            }
        } message: { Text("Your route, destination, latest location, agreed fare and help status will be visible to anyone with the link. You choose who receives it.") }
    }
}
