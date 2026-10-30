import Foundation

enum TripStatus: String, Codable, CaseIterable { case active, completed, cancelled }

struct TripRecord: Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var status: TripStatus
    var destination: String = "Practice trip"
    var agreedFare: Double? = nil
    var paidFare: Double? = nil
    var route: TripRoute? = nil
}

enum TripTransitionError: Error { case alreadyFinished, invalidEndDate, invalidStatus }

extension TripRecord {
    mutating func finish(as newStatus: TripStatus, at date: Date) throws {
        guard status == .active else { throw TripTransitionError.alreadyFinished }
        guard newStatus != .active else { throw TripTransitionError.invalidStatus }
        guard date >= startedAt else { throw TripTransitionError.invalidEndDate }
        status = newStatus
        endedAt = date
    }
}

struct TrustedContact: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var phone: String
}

enum ContactValidation {
    static func isValid(name: String, phone: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        phone.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "+0123456789 ()-.").contains($0) } &&
        (7...15).contains(phone.filter(\.isNumber).count)
    }
}


enum FareValidation {
    static func parse(_ text: String, decimalSeparator: String = ".") -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: decimalSeparator, with: ".")
        guard normalized.range(of: "^[0-9]+(?:[.][0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}
