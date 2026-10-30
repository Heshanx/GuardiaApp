import Combine
import Foundation

@MainActor final class GuardiaLaunchRequest: ObservableObject {
    enum Action { case dashboard, plan, checkIn }
    static let shared = GuardiaLaunchRequest()
    @Published var action: Action?
    func receive(_ url: URL) {
        guard url.scheme == "guardia" else { return }
        switch url.host {
        case "home": action = .dashboard
        case "plan": action = .plan
        case "check-in": action = .checkIn
        default: break
        }
    }
}
