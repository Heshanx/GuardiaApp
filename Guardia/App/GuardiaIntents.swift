import AppIntents
import Foundation

struct OpenGuardiaIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Guardia"
    static var description = IntentDescription("Open your protected trip dashboard.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        GuardiaLaunchRequest.shared.action = .dashboard
        return .result(dialog: "Guardia is ready. Unlock to see your trip.")
    }
}

struct PlanGuardiaTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan a Guardia trip"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        GuardiaLaunchRequest.shared.action = .plan
        return .result(dialog: "Opening your trip planner in Guardia.")
    }
}

struct GuardiaCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Guardia check-in"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        GuardiaLaunchRequest.shared.action = .checkIn
        return .result(dialog: "Open Guardia and unlock to review your check-in. No response has been sent yet.")
    }
}

struct GuardiaTripStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Guardia trip status"
    static var description = IntentDescription("Hear your saved trip status after device authentication. This does not verify GPS or contact emergency services.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard try await DeviceAuthenticator().unlock() else {
            return .result(dialog: "Unlock Guardia to hear your private trip status.")
        }
        let trips = try CoreDataTripRepository().load()
        guard let trip = trips.first(where: { $0.status == .active }) else {
            return .result(dialog: "You have no active trip in Guardia. Open the app to plan one.")
        }
        if let check = trip.route?.checkIns?.first(where: { $0.response == nil }) {
            if check.escalatedAt != nil {
                return .result(dialog: "Your trip has an unresolved help request. Open Guardia to review it and contact someone you trust. Guardia does not call emergency services.")
            }
            return .result(dialog: "Your trip needs a check-in. Open Guardia to review your route and respond.")
        }
        return .result(dialog: "You have an active trip in Guardia. No check-in is currently pending. Open the app for your latest location and sharing status.")
    }
}

struct GuardiaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenGuardiaIntent(), phrases: ["\(.applicationName)", "Open \(.applicationName)"], shortTitle: "Open Guardia", systemImageName: "shield.lefthalf.filled")
        AppShortcut(intent: PlanGuardiaTripIntent(), phrases: ["Plan a trip in \(.applicationName)", "Start a trip in \(.applicationName)"], shortTitle: "Plan trip", systemImageName: "point.topleft.down.to.point.bottomright.curvepath")
        AppShortcut(intent: GuardiaTripStatusIntent(), phrases: ["Trip status in \(.applicationName)", "Check my trip in \(.applicationName)"], shortTitle: "Trip status", systemImageName: "waveform")
        AppShortcut(intent: GuardiaCheckInIntent(), phrases: ["Check in with \(.applicationName)"], shortTitle: "Review check-in", systemImageName: "checkmark.shield")
    }
}
