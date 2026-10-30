import SwiftUI

struct FareEstimateView: View {
    let reference: FareReference
    let quote: Double?
    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "LKR").precision(.fractionLength(0)))
    }
    private var comparison: String? {
        guard let quote else { return nil }
        if quote < reference.lower { return "Below this estimate" }
        if quote <= reference.upper { return "Within this estimate" }
        return "Above this estimate"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(money(reference.median)).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.75)
            Text("\(money(reference.lower)) – \(money(reference.upper))")
                .font(.subheadline).foregroundStyle(.secondary)
            if let comparison { Label(comparison, systemImage: "info.circle").font(.subheadline) }
            Text(reference.dataSource == "synthetic" ? "Based on generated prices. Agree your fare with the driver." : "A guide based on recent fares. Agree your price with the driver.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 8)
    }
}
