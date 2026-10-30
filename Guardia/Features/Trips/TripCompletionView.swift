import SwiftUI

struct TripCompletionView: View {
    let trip: TripRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Image(systemName: trip.status == .completed ? "checkmark.circle" : "xmark.circle").font(.system(size: 52)).foregroundStyle(GuardiaStyle.accent)
                        Text(trip.status == .completed ? "Trip ended" : "Trip cancelled").font(.largeTitle.bold())
                        Text(trip.destination).font(.title3).foregroundStyle(.secondary)
                        GuardiaCard {
                            LabeledContent("Destination", value: trip.destination)
                            if let end = trip.endedAt { LabeledContent("Duration", value: "\(max(0, Int(end.timeIntervalSince(trip.startedAt) / 60))) min") }
                            if let fare = trip.agreedFare { LabeledContent("Agreed fare", value: fare.formatted(.currency(code: "LKR"))) }
                            Label((trip.route?.checkIns?.isEmpty ?? true) ? "No route check-ins raised" : "Route check-ins saved in trip details", systemImage: "checkmark.shield")
                        }
                        Text("Your trip record is saved on this device.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(28)
                }
                Button("Done") { dismiss() }.buttonStyle(GuardiaPrimaryButton()).padding(24)
            }.frame(maxWidth: 680).frame(maxWidth: .infinity).background(GuardiaStyle.background)
        }
    }
}
