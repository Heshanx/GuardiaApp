import SwiftUI

struct TripCompletionView: View {
    @ObservedObject var store: GuardiaStore
    let trip: TripRecord
    @State private var paid = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Image(systemName: trip.status == .completed ? "checkmark.circle" : "xmark.circle").font(.system(size: 52)).foregroundStyle(GuardiaStyle.accent)
                        Text(trip.status == .completed ? "Journey complete" : "Trip cancelled").font(.largeTitle.bold())
                        Text(trip.destination).font(.title3).foregroundStyle(.secondary)
                        GuardiaCard {
                            LabeledContent("Destination", value: trip.destination)
                            if let end = trip.endedAt { LabeledContent("Duration", value: "\(max(0, Int(end.timeIntervalSince(trip.startedAt) / 60))) min") }
                            if let fare = trip.agreedFare { LabeledContent("Agreed fare", value: fare.formatted(.currency(code: "LKR").precision(.fractionLength(0)))) }
                            Label((trip.route?.checkIns?.isEmpty ?? true) ? "No check-ins needed" : "Your check-ins are saved with this trip", systemImage: "checkmark.shield")
                        }
                        TextField("Fare paid (LKR, optional)", text: $paid).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        Text("Your trip record is saved on this device.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(28)
                }
                Button("Done") {
                    if paid.isEmpty { dismiss() }
                    else if let amount = FareValidation.parse(paid, decimalSeparator: Locale.current.decimalSeparator ?? "."), store.savePaidFare(tripID: trip.id, amount: amount) { dismiss() }
                }.disabled(!paid.isEmpty && FareValidation.parse(paid, decimalSeparator: Locale.current.decimalSeparator ?? ".") == nil).buttonStyle(GuardiaPrimaryButton()).padding(24)
            }.frame(maxWidth: 680).frame(maxWidth: .infinity).background(GuardiaStyle.background)
        }
    }
}
