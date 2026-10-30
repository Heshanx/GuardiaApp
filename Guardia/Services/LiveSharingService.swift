import Foundation
import Security
import Combine

@MainActor
final class LiveSharingService: ObservableObject {
    @Published private(set) var status = "Live sharing is off."
    @Published private(set) var sharingURL: URL?
    @Published private(set) var isEnabled = false
    @Published private(set) var busy = false
    private struct Identity: Codable { var uid: String; var refreshToken: String; var shares: [String] = [] }
    private var identity: Identity?
    private var token: String?
    private var expires = Date.distantPast
    private var shareID: String?
    private var tripID: UUID?
    private var lastUpload = Date.distantPast
    private var uploadTask: Task<Void, Never>?
    private var pendingTrip: TripRecord?
    private var generation = 0
    private let base = "https://firestore.googleapis.com/v1/projects/guardia-a63bd/databases/(default)/documents"
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.GuardiaApp", kSecAttrAccount as String: "FirebaseDeviceIdentity"]
    }
    init() {
        var query = keychainQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            identity = try? JSONDecoder().decode(Identity.self, from: data)
        }
    }
    private func saveIdentity() throws {
        guard let identity else { return }
        let data = try JSONEncoder().encode(identity)
        let result = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var query = keychainQuery; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw CloudError.message("Could not save cloud identity in Keychain.") }
        } else if result != errSecSuccess { throw CloudError.message("Could not update the cloud identity.") }
    }
    private func credentials() async throws -> (String, String) {
        if let identity, let token, expires > Date() { return (identity.uid, token) }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"), let configurationData = FileManager.default.contents(atPath: path),
              let config = try PropertyListSerialization.propertyList(from: configurationData, format: nil) as? [String: Any],
              config["PROJECT_ID"] as? String == "guardia-a63bd", let key = config["API_KEY"] as? String else { throw CloudError.message("Firebase configuration unavailable.") }
        let refresh = identity != nil
        let endpoint = refresh ? "https://securetoken.googleapis.com/v1/token?key=\(key)" : "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(key)"
        var request = URLRequest(url: URL(string: endpoint)!); request.httpMethod = "POST"; request.timeoutInterval = 20
        if let identity {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let value = identity.refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data("grant_type=refresh_token&refresh_token=\(value)".utf8)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"returnSecureToken":true}"#.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = json[refresh ? "user_id" : "localId"] as? String,
              let access = json[refresh ? "id_token" : "idToken"] as? String,
              let renewal = json[refresh ? "refresh_token" : "refreshToken"] as? String else {
            throw CloudError.message("Cloud sign-in failed. Enable Anonymous authentication in Firebase and check network/API-key settings.")
        }
        identity = Identity(uid: uid, refreshToken: renewal, shares: identity?.shares ?? [])
        try saveIdentity(); token = access; expires = Date().addingTimeInterval(3000)
        return (uid, access)
    }
    func enable(for trip: TripRecord) async {
        guard !busy, !isEnabled else { return }
        busy = true; defer { busy = false }
        generation += 1; let version = generation
        status = "Connecting live sharing…"
        do {
            let tracker = UserDefaults.standard.string(forKey: "trackerBaseURL") ?? "https://guardia-a63bd.web.app/track.html"
            guard var components = URLComponents(string: tracker), ["http", "https"].contains(components.scheme ?? ""), components.host != nil else { throw CloudError.message("Set a valid tracker page URL in Settings.") }
            _ = try await credentials()
            guard version == generation else { return }
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            identity?.shares.append(id); try saveIdentity()
            try await write(trip, id: id)
            guard version == generation else { try? await remove(id); return }
            components.fragment = id
            sharingURL = components.url; shareID = id; tripID = trip.id; isEnabled = true; lastUpload = Date()
            status = "Sharing active. Send the link to your contact; the tracker page must be served or deployed."
        } catch { status = error.localizedDescription }
    }
    func publish(_ trip: TripRecord, force: Bool = false) {
        guard isEnabled, tripID == trip.id, let id = shareID else { return }
        if uploadTask != nil { if force { pendingTrip = trip }; return }
        guard force || Date().timeIntervalSince(lastUpload) >= 10 else { return }
        let version = generation
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await write(trip, id: id)
                if version == generation { lastUpload = Date(); status = "Updated \(Date().formatted(date: .omitted, time: .standard)). Contacts see changes through the shared browser link." }
            } catch { if version == generation { status = "Cloud update failed; contact data may be stale. \(error.localizedDescription)" } }
            uploadTask = nil
            if version == generation, let next = pendingTrip { pendingTrip = nil; publish(next, force: true) }
        }
    }
    func stop() async {
        generation += 1; pendingTrip = nil
        let task = uploadTask; task?.cancel(); await task?.value; uploadTask = nil
        let id = shareID
        isEnabled = false; sharingURL = nil; shareID = nil; tripID = nil
        guard let id else { return }
        do { try await remove(id); status = "Cloud link revoked." }
        catch { status = "Could not revoke cloud link. Retry Delete cloud sharing data in Settings; public access expires within 24 hours." }
    }
    func deleteAll() async throws {
        await stop()
        guard identity != nil else { status = "No cloud sharing identity exists on this device."; return }
        let (uid, access) = try await credentials()
        var request = URLRequest(url: URL(string: base + ":runQuery")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let query: [String: Any] = ["structuredQuery": ["from": [["collectionId": "liveShares"]], "where": ["fieldFilter": ["field": ["fieldPath": "ownerUid"], "op": "EQUAL", "value": ["stringValue": uid]]]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: query)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CloudError.message("Could not verify cloud records for deletion. Check network and Firestore rules.") }
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        var ids = Set(identity?.shares ?? [])
        for row in rows {
            if let document = row["document"] as? [String: Any], let name = document["name"] as? String, let id = name.split(separator: "/").last { ids.insert(String(id)) }
        }
        for id in ids { try await remove(id) }
        status = "All live-sharing records for this device identity deleted."
    }
    private func write(_ trip: TripRecord, id: String) async throws {
        let (uid, access) = try await credentials()
        let latest = trip.route?.samples.last
        let event = trip.route?.checkIns?.last
        let state = event?.escalatedAt != nil && event?.response != "Confirmed okay" ? "help_requested" : event?.response == nil && event != nil ? "check_in" : "active"
        func string(_ text: String) -> [String: Any] { ["stringValue": text] }
        func number(_ value: Double) -> [String: Any] { ["doubleValue": value] }
        var fields: [String: Any] = ["ownerUid": string(uid), "destination": string(trip.destination), "state": string(state),
            "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())],
            "expiresAt": ["timestampValue": ISO8601DateFormatter().string(from: trip.startedAt.addingTimeInterval(86400))]]
        let original = trip.route?.expectedPath ?? []
        let strideSize = max(1, Int(ceil(Double(original.count) / 1000)))
        var overview = stride(from: 0, to: original.count, by: strideSize).map { original[$0] }
        if let last = original.last, overview.last != last { overview.append(last) }
        let points: [[String: Any]] = overview.map { point in
            ["mapValue": ["fields": ["lat": number(point.latitude), "lon": number(point.longitude)]]]
        }
        fields["route"] = ["arrayValue": ["values": points]]
        if let latest {
            fields["lat"] = number(latest.coordinate.latitude); fields["lon"] = number(latest.coordinate.longitude)
            fields["locationAt"] = ["timestampValue": ISO8601DateFormatter().string(from: latest.timestamp)]
        } else if let origin = trip.route?.origin {
            fields["lat"] = number(origin.latitude); fields["lon"] = number(origin.longitude)
            fields["locationAt"] = ["timestampValue": ISO8601DateFormatter().string(from: trip.route?.plannedAt ?? trip.startedAt)]
        }
        if let fare = trip.agreedFare { fields["agreedFare"] = number(fare) }
        var request = URLRequest(url: URL(string: base + "/liveShares/" + id)!)
        request.httpMethod = "PATCH"; request.timeoutInterval = 20
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CloudError.message("Cloud write failed. Create Firestore and publish the live-sharing rules.") }
    }
    private func remove(_ id: String) async throws {
        let (_, access) = try await credentials()
        var request = URLRequest(url: URL(string: base + "/liveShares/" + id)!)
        request.httpMethod = "DELETE"; request.timeoutInterval = 20
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let code = (response as? HTTPURLResponse)?.statusCode, code == 200 || code == 404 else { throw CloudError.message("A cloud share could not be deleted. Retry when online.") }
        identity?.shares.removeAll { $0 == id }; try saveIdentity()
    }
}
private enum CloudError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
