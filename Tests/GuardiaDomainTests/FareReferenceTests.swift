import Foundation
import Testing
@testable import GuardiaDomain

@Test func fareReferencesRejectOldSparseAndInvalidRanges() {
    let now = Date()
    #expect(FareReference(lower: 300, median: 350, upper: 400, sampleCount: 5, updatedAt: now).isReliable(at: now))
    #expect(!FareReference(lower: 300, median: 350, upper: 400, sampleCount: 4, updatedAt: now).isReliable(at: now))
    #expect(!FareReference(lower: 500, median: 350, upper: 400, sampleCount: 5, updatedAt: now).isReliable(at: now))
    #expect(!FareReference(lower: 300, median: 350, upper: 400, sampleCount: 5, updatedAt: now.addingTimeInterval(-91 * 86400)).isReliable(at: now))
    #expect(!FareReference(lower: 300, median: 350, upper: 400, sampleCount: 5, updatedAt: now.addingTimeInterval(60)).isReliable(at: now))
}
@Test func fareDistanceBandBoundariesAreStable() {
    #expect(FareReference.distanceBand(meters: 5000) == 1)
    #expect(FareReference.distanceBand(meters: 5001) == 2)
    #expect(FareReference.distanceBand(meters: 0) == nil)
    #expect(FareReference.distanceBand(meters: .infinity) == nil)
    #expect(FareReference.distanceBand(meters: 100001) == nil)
}
@Test func fareComparisonUsesPublishedRange() {
    let value = FareReference(lower: 300, median: 350, upper: 400, sampleCount: 5, updatedAt: Date())
    #expect(value.assessment(for: 400) == "Within the reported range")
    #expect(value.assessment(for: 450) == "Above the reported range")
    #expect(value.assessment(for: 550) == "Well above the reported range")
}
@Test func firestoreDocumentRequiresMatchingAreaAndPublishedData() throws {
    let json = #"{"fields":{"published":{"booleanValue":true},"currency":{"stringValue":"LKR"},"area":{"stringValue":"colombo"},"vehicle":{"stringValue":"tuktuk"},"distanceBand":{"integerValue":"1"},"lower":{"integerValue":"300"},"median":{"doubleValue":350},"upper":{"integerValue":"400"},"sampleCount":{"integerValue":"8"},"updatedAt":{"timestampValue":"2026-10-01T00:00:00Z"}}}"#
    let document = try JSONDecoder().decode(FirestoreFareDocument.self, from: Data(json.utf8))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z"))
    #expect(document.reference(area: "colombo", band: 1, now: now)?.median == 350)
    #expect(document.reference(area: "kandy", band: 1, now: now) == nil)
    #expect(document.reference(area: "colombo", band: 2, now: now) == nil)
}

@Test func syntheticReferencesRemainLabelledAndValidateProjection() throws {
    let json = #"{"fields":{"published":{"booleanValue":true},"currency":{"stringValue":"LKR"},"area":{"stringValue":"colombo"},"vehicle":{"stringValue":"tuktuk"},"distanceBand":{"integerValue":"1"},"lower":{"doubleValue":300},"median":{"doubleValue":350},"upper":{"doubleValue":400},"sampleCount":{"integerValue":"192"},"updatedAt":{"timestampValue":"2026-10-01T00:00:00Z"},"dataSource":{"stringValue":"synthetic"},"nextMonthMedian":{"doubleValue":353.5}}}"#
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z"))
    let doc = try JSONDecoder().decode(FirestoreFareDocument.self, from: Data(json.utf8))
    let reference = try #require(doc.reference(area: "colombo", band: 1, now: now))
    #expect(reference.dataSource == "synthetic")
    #expect(reference.nextMonthMedian == 353.5)
    let unknown = json.replacingOccurrences(of: "synthetic", with: "unverified")
    #expect(try JSONDecoder().decode(FirestoreFareDocument.self, from: Data(unknown.utf8)).reference(area: "colombo", band: 1, now: now) == nil)
}

@Test func syntheticModelUsesExactDistanceAndRejectsWrongBand() throws {
    func document(band: Int) throws -> FirestoreFareDocument {
        let json = """
        {"fields":{"published":{"booleanValue":true},"currency":{"stringValue":"LKR"},"area":{"stringValue":"colombo"},"vehicle":{"stringValue":"tuktuk"},"distanceBand":{"integerValue":"\(band)"},"lower":{"doubleValue":200},"median":{"doubleValue":350},"upper":{"doubleValue":500},"sampleCount":{"integerValue":"192"},"updatedAt":{"timestampValue":"2026-10-01T00:00:00Z"},"dataSource":{"stringValue":"synthetic"},"modelIntercept":{"doubleValue":100},"modelPerKm":{"doubleValue":100},"assumedMonthlyGrowth":{"doubleValue":0.01}}}
        """
        return try JSONDecoder().decode(FirestoreFareDocument.self, from: Data(json.utf8))
    }
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z"))
    let first = try document(band: 1)
    #expect(first.reference(area: "colombo", band: 1, now: now, distance: 1000)?.median == 200)
    #expect(first.reference(area: "colombo", band: 1, now: now, distance: 5001) == nil)
    let before = try #require(first.reference(area: "colombo", band: 1, now: now, distance: 5000))
    let after = try #require(document(band: 2).reference(area: "colombo", band: 2, now: now, distance: 5001))
    #expect(abs(after.median - before.median - 0.1) < 0.00001)
    #expect(abs((before.nextMonthMedian ?? 0) - 606) < 0.00001)
}
