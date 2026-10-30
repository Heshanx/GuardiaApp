import Foundation

struct FareReference {
    let lower: Double
    let median: Double
    let upper: Double
    let sampleCount: Int
    let updatedAt: Date
    var dataSource: String = "reported"
    var nextMonthMedian: Double? = nil
    func isReliable(at now: Date) -> Bool {
        lower.isFinite && median.isFinite && upper.isFinite && lower > 0 && lower <= median && median <= upper && sampleCount >= 5 &&
        now.timeIntervalSince(updatedAt) >= 0 && now.timeIntervalSince(updatedAt) <= 90 * 86400
    }
    func assessment(for quote: Double) -> String {
        if quote < lower { return "Below the reported range" }
        if quote <= upper { return "Within the reported range" }
        if quote <= upper * 1.25 { return "Above the reported range" }
        return "Well above the reported range"
    }
    static func distanceBand(meters: Double) -> Int? {
        guard meters.isFinite, meters > 0, meters <= 100_000 else { return nil }
        return max(1, Int(ceil(meters / 5000)))
    }
}

struct FirestoreFareDocument: Decodable {
    struct Value: Decodable {
        let doubleValue: Double?
        let integerValue: String?
        let stringValue: String?
        let booleanValue: Bool?
        let timestampValue: String?
        var number: Double? { doubleValue ?? integerValue.flatMap(Double.init) }
    }
    let fields: [String: Value]
    func reference(area: String, band: Int, now: Date, distance: Double? = nil) -> FareReference? {
        let f = fields
        guard f["published"]?.booleanValue == true, f["currency"]?.stringValue == "LKR",
              f["area"]?.stringValue == area, f["vehicle"]?.stringValue == "tuktuk", f["distanceBand"]?.number == Double(band),
              let lower = f["lower"]?.number, let median = f["median"]?.number, let upper = f["upper"]?.number,
              let count = f["sampleCount"]?.number, count.isFinite, count >= 5, count <= 1_000_000, count.rounded() == count,
              let timestamp = f["updatedAt"]?.timestampValue else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: timestamp)
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: timestamp) }
        guard let date else { return nil }
        var value = FareReference(lower: lower, median: median, upper: upper, sampleCount: Int(count), updatedAt: date)
        let source = f["dataSource"]?.stringValue ?? "reported"
        guard ["reported", "synthetic"].contains(source) else { return nil }
        value.dataSource = source
        if source == "synthetic", let future = f["nextMonthMedian"]?.number, future.isFinite, future > 0 {
            value.nextMonthMedian = future
        }
        if source == "synthetic", let distance {
            guard FareReference.distanceBand(meters: distance) == band,
                  let intercept = f["modelIntercept"]?.number, intercept.isFinite,
                  let rate = f["modelPerKm"]?.number, rate.isFinite, rate > 0 else { return nil }
            let estimate = intercept + rate * distance / 1000
            guard estimate.isFinite, estimate > 0 else { return nil }
            var adjusted = FareReference(lower: max(1, estimate - (median - lower)), median: estimate,
                                         upper: estimate + (upper - median), sampleCount: Int(count), updatedAt: date)
            adjusted.dataSource = source
            if let growth = f["assumedMonthlyGrowth"]?.number, growth.isFinite, (0...1).contains(growth) {
                adjusted.nextMonthMedian = estimate * (1 + growth)
            }
            value = adjusted
        }
        return value.isReliable(at: now) ? value : nil
    }
}
