import Foundation
import Network
import Combine

@MainActor
final class ConnectionStatus: ObservableObject {
    @Published private(set) var summary = "Checking connection…"
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let value: String
            if path.status != .satisfied { value = "No available network connection" }
            else if path.usesInterfaceType(.wifi) { value = "Wi-Fi connection available" }
            else if path.usesInterfaceType(.cellular) { value = "Mobile data connection available" }
            else { value = "Network connection available" }
            Task { @MainActor [weak self] in self?.summary = value }
        }
        monitor.start(queue: DispatchQueue(label: "Guardia.connection"))
    }
    deinit { monitor.cancel() }
}
