import SwiftUI

struct RouteCheckInSheet: View {
    @ObservedObject var store: GuardiaStore
    let check: RouteCheckIn
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: check.escalatedAt == nil ? "checkmark.shield" : "person.2.wave.2")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(GuardiaStyle.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(check.escalatedAt == nil ? "Are you okay?" : "Reach someone you trust")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(check.escalatedAt == nil
                         ? (check.trigger == "manual" ? "Take a moment to let us know." : "Your journey looks different from the route you planned.")
                         : "Send a message or call a trusted contact.")
                        .foregroundStyle(.secondary)
                }
                if check.escalatedAt == nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Help options open in \(max(0, Int(ceil(check.deadline.timeIntervalSince(context.date))))) seconds")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .task(id: context.date) { if context.date >= check.deadline { store.escalateCheckIn() } }
                    }
                    Button("I’m okay") { store.respondToCheckIn("Confirmed okay") }.buttonStyle(GuardiaPrimaryButton())
                    Button("I need help") { store.escalateCheckIn() }.buttonStyle(.bordered).controlSize(.large)
                        .frame(maxWidth: .infinity)
                } else {
                    TrustedContactAlertView(store: store, check: check)
                    if !store.contacts.isEmpty {
                        Divider()
                        ForEach(store.contacts) { contact in
                            if let url = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }), UIApplication.shared.canOpenURL(url) {
                                Link(destination: url) { Label("Call \(contact.name)", systemImage: "phone") }
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    Button("I’m okay now") { store.respondToCheckIn("Confirmed okay") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                Text("Messages need your confirmation to send. Guardia doesn’t contact emergency services.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(GuardiaStyle.background)
    }
}
