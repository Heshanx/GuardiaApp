import SwiftUI

@main
@MainActor
struct GuardiaApp: App {
    var body: some Scene {
        WindowGroup { BootstrapView() }
    }
}

@MainActor
private struct BootstrapView: View {
    @State private var store: GuardiaStore?
    @State private var startupError: String?

    var body: some View {
        Group {
            if let store { GuardiaRootView(store: store) }
            else if let startupError {
                ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError))
            } else { ProgressView("Opening Guardia") }
        }
        .task {
            guard store == nil, startupError == nil else { return }
            do {
                store = try GuardiaStore(repository: CoreDataTripRepository(), authenticator: DeviceAuthenticator(),
                                         contactRepository: ContactRepository(), location: TripLocationService())
            } catch { startupError = error.localizedDescription }
        }
    }
}
