import SwiftUI
import MessageUI

/// Messages handles transport. A sent result is not a recipient delivery receipt.
struct TrustedContactAlertView: View {
    @ObservedObject var store: GuardiaStore
    @ObservedObject private var sharing: LiveSharingService
    let check: RouteCheckIn
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: HelpMessageDraft?
    @State private var attemptedAutomaticDraft = false
    @State private var resultText: String?

    init(store: GuardiaStore, check: RouteCheckIn) {
        self.store = store
        self.sharing = store.sharing
        self.check = check
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Alert trusted contacts", systemImage: "message.fill").font(.headline)
            if store.contacts.isEmpty {
                Text("Add a trusted contact to send a help message.")
            } else {
                Text("To: " + store.contacts.map(\.name).joined(separator: ", ")).font(.subheadline)
                if MFMessageComposeViewController.canSendText() {
                    Button { prepare() } label: { Label("Message contacts", systemImage: "paperplane") }
                        .buttonStyle(.borderedProminent)
                    Text("Review and tap Send. A group message may share contact numbers. Carrier charges may apply.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(store.contacts) { contact in
                        Button("Message only \(contact.name)") { prepare(recipients: [contact.phone]) }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Text("Messages is unavailable on this device. Call a contact below, or copy the help message into another messaging app.")
                }
                Button("Copy help message") {
                    UIPasteboard.general.string = messageBody
                    resultText = "Message copied. Ready to paste and send."
                }
            }
            if let resultText { Text(resultText).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
            Text(sharing.sharingURL == nil ? "Your last available location will be included." : "Your live trip link is included.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $draft) { message in
            HelpMessageComposer(draft: message) { result in
                switch result {
                case .sent: resultText = "Message sent. Delivery depends on your messaging service."
                case .cancelled: resultText = "Message cancelled."
                case .failed: resultText = "Messages could not send this alert. Try again or call your contact."
                @unknown default: resultText = "Check Messages to confirm it was sent."
                }
                draft = nil
            }.ignoresSafeArea()
        }
        .task { prepareAutomaticallyIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { prepareAutomaticallyIfNeeded() } }
    }

    private var messageBody: String {
        var lines = ["Guardia help request: I may need help on my trip. Please contact me.",
                     "Help requested: \(check.escalatedAt?.formatted(date: .abbreviated, time: .shortened) ?? check.raisedAt.formatted(date: .abbreviated, time: .shortened))."]
        if let url = sharing.sharingURL {
            lines.append("Follow my trip: \(url.absoluteString)")
        }
        if let sample = store.activeTrip?.route?.samples.last {
            lines.append("Last saved location (\(sample.timestamp.formatted(date: .abbreviated, time: .shortened))): https://maps.apple.com/?ll=\(sample.coordinate.latitude),\(sample.coordinate.longitude)")
            lines.append("This saved location may be out of date.")
        } else if sharing.sharingURL == nil {
            lines.append("My location isn’t available. Please call me.")
        }
        lines.append("Guardia has not contacted emergency services.")
        return lines.joined(separator: "\n")
    }

    private func prepareAutomaticallyIfNeeded() {
        guard !attemptedAutomaticDraft, scenePhase == .active, store.isUnlocked,
              !store.contacts.isEmpty, MFMessageComposeViewController.canSendText() else { return }
        attemptedAutomaticDraft = true
        prepare()
    }

    private func prepare(recipients: [String]? = nil) {
        guard store.isUnlocked, MFMessageComposeViewController.canSendText() else { return }
        let numbers = (recipients ?? store.contacts.map(\.phone)).map { $0.filter { $0.isNumber || $0 == "+" } }.filter { !$0.isEmpty }
        guard !numbers.isEmpty else { resultText = "No valid contact numbers are available."; return }
        draft = HelpMessageDraft(recipients: numbers, body: messageBody)
    }
}

private struct HelpMessageDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

private struct HelpMessageComposer: UIViewControllerRepresentable {
    let draft: HelpMessageDraft
    let completion: (MessageComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = draft.recipients
        controller.body = draft.body
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { completion(result) }
    }
}
