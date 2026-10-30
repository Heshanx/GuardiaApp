import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let state: String
        let updatedAt: Date
    }
    let tripID: String
    let startedAt: Date
}
