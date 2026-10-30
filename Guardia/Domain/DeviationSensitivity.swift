import Foundation

/// Corridor tolerance is measured after accounting for reported GPS accuracy.
enum DeviationSensitivity: String, CaseIterable {
    case attentive, balanced, relaxed
    var meters: Double {
        switch self {
        case .attentive: return 150
        case .balanced: return 300
        case .relaxed: return 500
        }
    }
}
