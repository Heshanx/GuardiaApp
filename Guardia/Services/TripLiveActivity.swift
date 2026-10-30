import ActivityKit
import Foundation

@MainActor
final class TripLiveActivity {
    private var lastState: String?
    private var lastUpdate = Date.distantPast
    func update(_ trip: TripRecord) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let pending = trip.route?.checkIns?.first { $0.response == nil }
        let state = pending?.escalatedAt != nil ? "Help requested · open Guardia" : pending != nil ? "Route check-in · open Guardia" : "Trip in progress"
        let content = ActivityContent(state: TripActivityAttributes.ContentState(state: state, updatedAt: Date()), staleDate: Date().addingTimeInterval(120))
        if let activity = Activity<TripActivityAttributes>.activities.first(where: { $0.attributes.tripID == trip.id.uuidString }) {
            guard state != lastState || Date().timeIntervalSince(lastUpdate) > 60 else { return }
            lastState = state; lastUpdate = Date()
            Task { await activity.update(content) }
        } else {
            do {
                _ = try Activity.request(attributes: TripActivityAttributes(tripID: trip.id.uuidString, startedAt: trip.startedAt), content: content, pushType: nil)
                lastState = state; lastUpdate = Date()
            } catch { /* Local trip recording remains available if activities are denied. */ }
        }
    }
    func end(_ trip: TripRecord) {
        for activity in Activity<TripActivityAttributes>.activities where activity.attributes.tripID == trip.id.uuidString {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        lastState = nil
    }
}
