import Foundation

enum TripStatus: String, Codable, CaseIterable {
    case active, completed, cancelled
}

struct TripRecord: Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var status: TripStatus
}

enum TripTransitionError: Error {
    case alreadyFinished, invalidEndDate, invalidStatus
}

extension TripRecord {
    mutating func finish(as newStatus: TripStatus, at date: Date) throws {
        guard status == .active else { throw TripTransitionError.alreadyFinished }
        guard newStatus != .active else { throw TripTransitionError.invalidStatus }
        guard date >= startedAt else { throw TripTransitionError.invalidEndDate }
        status = newStatus
        endedAt = date
    }
}
