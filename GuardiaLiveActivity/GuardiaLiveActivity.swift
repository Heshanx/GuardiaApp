import WidgetKit
import SwiftUI
import ActivityKit

@main
struct GuardiaWidgets: WidgetBundle {
    var body: some Widget {
        GuardiaQuickWidget()
        GuardiaTripActivity()
    }
}

struct GuardiaTripActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack {
                Image(systemName: "shield.lefthalf.filled").font(.title).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Guardia trip").font(.headline)
                    Text(context.state.state).font(.subheadline)
                    Text(context.attributes.startedAt, style: .timer).monospacedDigit()
                }
                Spacer()
            }.padding().activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Guardia", systemImage: "shield.lefthalf.filled") }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.startedAt, style: .timer).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.state) }
            } compactLeading: { Image(systemName: "shield.lefthalf.filled").foregroundStyle(.cyan) }
              compactTrailing: { Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 52) }
              minimal: { Image(systemName: "shield.lefthalf.filled") }
        }
    }
}
