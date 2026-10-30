import SwiftUI
import WidgetKit

private struct GuardiaEntry: TimelineEntry { let date: Date }
private struct GuardiaProvider: TimelineProvider {
    func placeholder(in context: Context) -> GuardiaEntry { GuardiaEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (GuardiaEntry) -> Void) { completion(GuardiaEntry(date: .now)) }

    //quick actions like periodic refreshes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GuardiaEntry>) -> Void) {
        completion(Timeline(entries: [GuardiaEntry(date: .now)], policy: .never))
    }
}

struct GuardiaQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GuardiaQuickAccess", provider: GuardiaProvider()) { _ in
            GuardiaQuickView().containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.03, green: 0.12, blue: 0.24), Color(red: 0.06, green: 0.28, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .configurationDisplayName("Guardia quick access")
        .description("Plan a trip, open your dashboard, or review a check-in. Unlock in Guardia to continue.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct GuardiaQuickView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "shield.lefthalf.filled").font(.title).widgetURL(URL(string: "guardia://home"))
        case .accessoryInline:
            Label("Open Guardia", systemImage: "shield.lefthalf.filled").widgetURL(URL(string: "guardia://home"))
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Guardia", systemImage: "shield.lefthalf.filled").font(.headline)
                Text("Open your trip").font(.caption)
            }.widgetURL(URL(string: "guardia://home"))
        default:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "shield.lefthalf.filled").foregroundStyle(.cyan); Text("Guardia").font(.headline) }
                    Spacer(minLength: 0)
                    Text("Your next ride,\nwith confidence.").font(.system(.title3, design: .rounded, weight: .semibold)).minimumScaleFactor(0.8)
                    Label("Open your trip", systemImage: "arrow.up.right").font(.caption).foregroundStyle(.cyan)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if family == .systemMedium {
                    VStack(spacing: 10) {
                        action("Plan trip", symbol: "point.topleft.down.to.point.bottomright.curvepath", path: "plan")
                        action("Check-in", symbol: "checkmark.shield", path: "check-in")
                    }.frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
            .widgetURL(URL(string: "guardia://home"))
        }
    }
    private func action(_ title: String, symbol: String, path: String) -> some View {
        Link(destination: URL(string: "guardia://\(path)")!) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityHint("Opens Guardia; authentication is required")
    }
}
