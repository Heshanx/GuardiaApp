import SwiftUI

struct RouteCheckInSheet: View {
    @ObservedObject var store: GuardiaStore
    let check: RouteCheckIn
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.largeTitle).foregroundStyle(GuardiaStyle.accent)
            Text(check.trigger == "manual" ? "Manual check-in" : "Route looks different than expected").font(.title2.bold()).multilineTextAlignment(.center)
            Text(check.trigger == "manual" ? "You raised this check-in. Are you okay?" : "You were about \(Int(check.distance)) m from the expected route. Are you okay?").foregroundStyle(.secondary).multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(check.escalatedAt == nil ? "\(max(0, Int(ceil(check.deadline.timeIntervalSince(context.date))))) seconds to escalation" : "Help requested")
                    .font(.title2.monospacedDigit()).foregroundStyle(GuardiaStyle.accent)
                    .task(id: context.date) { if context.date >= check.deadline { store.escalateCheckIn() } }
            }
            HStack {
                Button("I’m fine") { store.respondToCheckIn("Confirmed okay") }.buttonStyle(.bordered).controlSize(.large)
                Button("Need help") { store.escalateCheckIn() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            if check.escalatedAt != nil {
                ForEach(store.contacts) { contact in
                    if let url = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }) {
                        Link("Call \(contact.name)", destination: url).buttonStyle(.bordered)
                    }
                }
                Button("Back to trip") { store.respondToCheckIn("Help requested") }
            }
            Text("Without live sharing enabled, contacts cannot receive this alert. Call directly if you need help. Countdown execution can be interrupted if iOS suspends or closes Guardia.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity).background(GuardiaStyle.background)
    }
}
