import Foundation
import Security
import Combine

@MainActor
final class LiveSharingService: ObservableObject {
    @Published private(set) var userNotice: String?
    @Published private(set) var status = "Live sharing is off."
    @Published private(set) var sharingURL: URL?
    @Published private(set) var isEnabled = false
    @Published private(set) var busy = false
    @Published private(set) var lastUploadedAt: Date?
    @Published private(set) var expiresAt: Date?
    private struct ShareSession: Codable {
        let id: String
        let tripID: UUID
        let url: URL
        let expiresAt: Date
    }
    private struct Identity: Codable {
        var uid: String
        var refreshToken: String
        var shares: [String] = []
        var session: ShareSession? = nil
    }
    private struct Configuration {
        let project: String
        let key: String
        static func load() throws -> Self {
            guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let project = values["PROJECT_ID"] as? String, project == "guardia-a63bd",
                  values["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier,
                  let key = values["API_KEY"] as? String, !key.isEmpty else {
                throw CloudError.message("Firebase configuration is missing or mismatched. Add GoogleService-Info.plist for guardia-a63bd / com.GuardiaApp to the app target.")
            }
            return Self(project: project, key: key)
        }
    }
    private let network: URLSession
    private var identity: Identity?
    private var identityReadError: OSStatus?
    private var token: String?
    private var tokenExpires = Date.distantPast
    private var lastUpload = Date.distantPast
    private var lastAttempt = Date.distantPast
    private var pendingForced = false
    private var uploadTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var latestTrip: TripRecord?
    private var pendingTrip: TripRecord?
    private var generation = 0
    private let base = "https://firestore.googleapis.com/v1/projects/guardia-a63bd/databases/(default)/documents"
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.GuardiaApp", kSecAttrAccount as String: "FirebaseDeviceIdentity"]
    }
    init(network: URLSession = .shared) {
        self.network = network
        var query = keychainQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecSuccess, let data = result as? Data {
            do { identity = try JSONDecoder().decode(Identity.self, from: data) }
            catch { status = "The saved cloud identity could not be read. Your old sharing links may require revocation in Firebase Console."; identityReadError = errSecDecode }
        } else if code != errSecItemNotFound { identityReadError = code }
    }
    private func saveIdentity() throws {
        guard let identity else { return }
        let data = try JSONEncoder().encode(identity)
        let result = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var query = keychainQuery; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw CloudError.message("Could not save cloud identity in Keychain.") }
        } else if result != errSecSuccess { throw CloudError.message("Could not update the cloud identity in Keychain (\(result)).") }
    }
    /// Decode and report Firebase's real error, without logging keys or tokens.
    private func send(_ input: URLRequest, operation: String) async throws -> Data {
        var request = input
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CloudError.message("\(operation): no server response.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404, operation == "Revoke sharing link" { return Data() }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            let advice: String
            if http.statusCode == 404, operation == "Tracker page" {
                advice = " Deploy Backend/public to Firebase Hosting. The tracker page must exist before a sharing link can work."
            } else if http.statusCode == 403, request.url?.host == "firestore.googleapis.com" {
                advice = " Publish Backend/firestore.rules from this app: the private-history-only rules do not allow /liveShares. Also check any App Check enforcement."
            } else if detail.contains("OPERATION_NOT_ALLOWED") { advice = " Enable Anonymous sign-in in Firebase Authentication." }
            else { advice = "" }
            throw CloudError.message("\(operation) (\(http.statusCode)): \(detail).\(advice)")
        }
        return data
    }
    private func credentials() async throws -> (String, String) {
        if let identity, let token, tokenExpires > Date() { return (identity.uid, token) }
        if let identityReadError { throw CloudError.message("Could not access the saved Firebase identity (\(identityReadError)). Unlock the device and retry; do not erase credentials for active links.") }
        let config = try Configuration.load()
        let refresh = identity != nil
        let endpoint = refresh ? "https://securetoken.googleapis.com/v1/token?key=\(config.key)" : "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(config.key)"
        var request = URLRequest(url: URL(string: endpoint)!); request.httpMethod = "POST"
        if let identity {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let value = identity.refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data("grant_type=refresh_token&refresh_token=\(value)".utf8)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"returnSecureToken":true}"#.utf8)
        }
        let data = try await send(request, operation: "Firebase sign-in")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = json[refresh ? "user_id" : "localId"] as? String,
              let access = json[refresh ? "id_token" : "idToken"] as? String,
              let renewal = json[refresh ? "refresh_token" : "refreshToken"] as? String else {
            throw CloudError.message("Firebase returned an invalid sign-in response.")
        }
        identity = Identity(uid: uid, refreshToken: renewal, shares: identity?.shares ?? [], session: identity?.session)
        try saveIdentity()
        token = access
        let seconds = (json[refresh ? "expires_in" : "expiresIn"] as? String).flatMap(Double.init) ?? 3600
        tokenExpires = Date().addingTimeInterval(max(0, seconds - 60))
        return (uid, access)
    }
    private func trackerURL() throws -> URL {
        let value = UserDefaults.standard.string(forKey: "trackerBaseURL") ?? "https://guardia-a63bd.web.app/track.html"
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme ?? ""), components.host != nil,
              components.user == nil, components.password == nil, let url = components.url else {
            throw CloudError.message("Set a valid tracker page URL in Settings.")
        }
        return url
    }
    private func verifyTracker(_ url: URL) async throws {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.fragment = nil
        let data = try await send(URLRequest(url: components.url!), operation: "Tracker page")
        guard let html = String(data: data, encoding: .utf8), html.contains("Guardia live trip"), html.contains("guardia-a63bd") else {
            throw CloudError.message("The tracker URL does not contain the Guardia tracker. Deploy Backend/public with Firebase Hosting, or correct the URL in Settings.")
        }
    }
    func checkSetup() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await credentials()
            try await verifyTracker(trackerURL())
            status = "Firebase sign-in and tracker page work. Enable sharing in an active trip to verify the live-share write/read permissions."
        } catch { status = error.localizedDescription }
    }
    func enable(for trip: TripRecord) async {
        guard !busy, !isEnabled, trip.status == .active else { return }
        guard trip.route != nil else {
            status = "This check-in-only trip has no route or GPS recording. Start a route trip to share live location."
            return
        }
        busy = true; defer { busy = false }
        generation += 1; let version = generation
        userNotice = nil
        status = "Checking Firebase and tracker page…"
        do {
            let tracker = try trackerURL()
            _ = try await credentials()
            try await verifyTracker(tracker)
            guard version == generation else { return }
            if let previous = identity?.session {
                try await remove(previous.id)
                identity?.session = nil
                try saveIdentity()
            }
            guard version == generation else { return }
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            var components = URLComponents(url: tracker, resolvingAgainstBaseURL: false)!
            components.fragment = id
            let session = ShareSession(id: id, tripID: trip.id, url: components.url!, expiresAt: Date().addingTimeInterval(86340))
            identity?.shares.append(id); try saveIdentity()
            do {
                try await write(trip, session: session, create: true)
                // Confirm that an unauthenticated recipient can open this exact document.
                _ = try await send(URLRequest(url: URL(string: base + "/liveShares/" + id)!), operation: "Recipient link read")
                guard version == generation else { try? await remove(id); return }
                identity?.session = session
                try saveIdentity()
            } catch {
                if identity?.session?.id == id { identity?.session = nil; try? saveIdentity() }
                try? await remove(id)
                throw error
            }
            activate(session, trip: trip)
            userNotice = nil
            status = "Sharing active. Send the link to your trusted contact."
        } catch {
            if version == generation { userNotice = "Couldn’t start sharing. Please try again."; status = error.localizedDescription }
        }
    }
    private func activate(_ session: ShareSession, trip: TripRecord) {
        latestTrip = trip
        sharingURL = session.url; expiresAt = session.expiresAt; isEnabled = true
        lastUpload = Date(); lastAttempt = lastUpload; lastUploadedAt = lastUpload
        startHeartbeat()
    }
    /// The saved session is recovered only for its matching active trip.
    func restore(for trip: TripRecord?) async {
        guard !busy, !isEnabled, let session = identity?.session else { return }
        guard let trip, trip.route != nil, trip.id == session.tripID, session.expiresAt > Date() else { await stop(); return }
        busy = true; defer { busy = false }
        let version = generation
        do {
            _ = try await credentials()
            try await verifyTracker(session.url)
            _ = try await send(URLRequest(url: URL(string: base + "/liveShares/" + session.id)!), operation: "Restore sharing link")
            guard version == generation else { return }
            activate(session, trip: trip)
            lastUploadedAt = nil // Wait for a confirmed write before claiming a new cloud update.
            status = "Saved sharing link restored. Resume recording if location is paused."
            publish(trip, force: true)
        } catch { if version == generation { userNotice = "Sharing hasn’t resumed. Try sharing your trip again."; status = "Sharing could not resume. \(error.localizedDescription)" } }
    }
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, isEnabled, let trip = latestTrip else { return }
                if let expiry = expiresAt, expiry <= Date() { heartbeatTask = nil; await stop(); status = "Sharing link expired. Enable sharing again for a new link."; return }
                publish(trip, force: true)
            }
        }
    }
    func publish(_ trip: TripRecord, force: Bool = false) {
        guard isEnabled, let session = identity?.session, session.tripID == trip.id else { return }
        latestTrip = trip
        if uploadTask != nil { pendingTrip = trip; pendingForced = pendingForced || force; return }
        guard force || Date().timeIntervalSince(lastAttempt) >= 10 else { return }
        lastAttempt = Date()
        let version = generation
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await write(trip, session: session, create: false)
                if version == generation {
                    lastUpload = Date(); lastAttempt = lastUpload; lastUploadedAt = lastUpload
                    userNotice = nil
                    status = "Live sharing updated \(lastUpload.formatted(date: .omitted, time: .standard))."
                }
            } catch {
                if version == generation { userNotice = "Updates paused. Your contact may see an older location."; status = "Update failed; contact data may be stale. \(error.localizedDescription)" }
            }
            uploadTask = nil
            if version == generation, let next = pendingTrip { let urgent = pendingForced; pendingTrip = nil; pendingForced = false; publish(next, force: urgent) }
        }
    }
    func stop() async {

        generation += 1
        isEnabled = false; sharingURL = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        while busy {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        busy = true; defer { busy = false }
        pendingTrip = nil; pendingForced = false; latestTrip = nil
        let task = uploadTask; task?.cancel(); await task?.value; uploadTask = nil
        let id = identity?.session?.id
        isEnabled = false; sharingURL = nil; expiresAt = nil; lastUploadedAt = nil
        identity?.session = nil
        do {
            try saveIdentity()
            guard let id else { status = "Live sharing is off."; return }
            try await remove(id)
            userNotice = nil; status = "Cloud link revoked."
        } catch { userNotice = "Couldn’t remove your link. Try Remove shared links in Settings. Access ends when the link expires."; status = "Could not revoke cloud link. Retry Delete cloud sharing data in Settings; access ends at its original expiry. \(error.localizedDescription)" }
    }
    func deleteAll() async throws {
        guard !busy else { throw CloudError.message("Wait for the current sharing request, then retry deletion.") }
        await stop()
        busy = true; defer { busy = false }
        guard identity != nil else { status = "No cloud sharing identity exists on this device."; return }
        let (uid, access) = try await credentials()
        var request = URLRequest(url: URL(string: base + ":runQuery")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": ["from": [["collectionId": "liveShares"]], "where": ["fieldFilter": ["field": ["fieldPath": "ownerUid"], "op": "EQUAL", "value": ["stringValue": uid]]]]])
        let data = try await send(request, operation: "List your sharing records")
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        var ids = Set(identity?.shares ?? [])
        for row in rows {
            if let document = row["document"] as? [String: Any], let name = document["name"] as? String, let id = name.split(separator: "/").last { ids.insert(String(id)) }
        }
        for id in ids { try await remove(id) }
        status = "All live-sharing records for this device identity deleted."
    }
    private func write(_ trip: TripRecord, session: ShareSession, create: Bool) async throws {
        let (uid, access) = try await credentials()
        let fields = try LiveSharePayload.fields(trip: trip, owner: uid, expiresAt: session.expiresAt, now: Date())

        let url = URL(string: base + "/liveShares/" + session.id + "?currentDocument.exists=" + (create ? "false" : "true"))!
        var request = URLRequest(url: url); request.httpMethod = "PATCH"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try await send(request, operation: "Live-share write")
    }
    private func remove(_ id: String) async throws {
        let (_, access) = try await credentials()
        var request = URLRequest(url: URL(string: base + "/liveShares/" + id)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        _ = try await send(request, operation: "Revoke sharing link")
        identity?.shares.removeAll { $0 == id }; try saveIdentity()
    }
}
private enum CloudError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
