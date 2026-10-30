import SwiftUI
import FirebaseCore
import AppIntents

@main
@MainActor
struct GuardiaApp: App {
    @UIApplicationDelegateAdaptor(GuardiaAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { BootstrapView().onOpenURL { GuardiaLaunchRequest.shared.receive($0) } }
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
                ContentUnavailableView("Unable to open your trips", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError))
            } else { ProgressView("Opening Guardia") }
        }
        .task {
            guard store == nil, startupError == nil else { return }
            await Task.yield()
            do {
                store = try GuardiaStore(repository: CoreDataTripRepository(), authenticator: DeviceAuthenticator(),
                                         contactRepository: ContactRepository(), location: TripLocationService())
            } catch { startupError = "Please close Guardia and try again. Your saved trips have not been removed." }
        }
    }
}

@MainActor
final class GuardiaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil,
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path),
           options.bundleID == Bundle.main.bundleIdentifier {
            FirebaseApp.configure(options: options)
        }
        DestinationGeofence.shared.restore()
        GuardiaShortcuts.updateAppShortcutParameters()
        return true
    }
}
