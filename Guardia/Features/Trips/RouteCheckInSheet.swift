import SwiftUI

struct RouteCheckInSheet: View {
    @ObservedObject var store: GuardiaStore
    let check: RouteCheckIn
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.largeTitle).foregroundStyle(GuardiaStyle.accent)
            Text("Route looks different than expected").font(.title2.bold()).multilineTextAlignment(.center)
            Text("You were about \(Int(check.distance)) m from the expected route. Are you okay?").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("I’m fine") { store.respondToCheckIn("Confirmed okay") }.buttonStyle(.bordered).controlSize(.large)
                Button("Need help") { store.respondToCheckIn("Help requested locally; contacts not notified") }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("Contact delivery is not connected. If you need help, call someone directly. This check-in has no automatic escalation countdown.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity).background(GuardiaStyle.background)
    }
}
