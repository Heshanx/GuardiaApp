import Foundation
import Testing
@testable import GuardiaDomain

@Test func manualAndAutomaticCheckInsShareThirtySecondDeadline() throws {
    let raised = Date(timeIntervalSince1970: 1000)
    let automatic = RouteCheckIn(id: UUID(), raisedAt: raised, distance: 500)
    let manual = RouteCheckIn(id: UUID(), raisedAt: raised, distance: 0, trigger: "manual")
    #expect(automatic.deadline == manual.deadline)
    #expect(manual.deadline == raised.addingTimeInterval(30))
    var escalated = manual
    escalated.escalatedAt = raised.addingTimeInterval(30)
    let copy = try JSONDecoder().decode(RouteCheckIn.self, from: JSONEncoder().encode(escalated))
    #expect(copy == escalated)
}

@Test func previousCheckInPayloadStillDecodes() throws {
    let json = #"{"id":"E118AA22-92F4-454A-A292-B70F1A81B542","raisedAt":1000,"distance":500}"#
    let check = try JSONDecoder().decode(RouteCheckIn.self, from: Data(json.utf8))
    #expect(check.trigger == nil)
    #expect(check.escalatedAt == nil)
    #expect(check.response == nil)
}
