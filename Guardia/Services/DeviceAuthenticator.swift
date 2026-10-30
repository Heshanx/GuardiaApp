import LocalAuthentication

@MainActor
protocol DeviceAuthenticating {
    func unlock() async throws -> Bool
}

@MainActor
struct DeviceAuthenticator: DeviceAuthenticating {
    func unlock() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        // System-managed device passcode fallback; not a remote account login.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: "Guardia.Authentication", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Set up a device passcode to unlock Guardia."])
        }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: "Unlock your private Guardia trip history.")
        } catch let failure as LAError where [.userCancel, .systemCancel, .appCancel].contains(failure.code) { return false }
    }
}
