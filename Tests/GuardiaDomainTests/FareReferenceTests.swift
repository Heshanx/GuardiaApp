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
