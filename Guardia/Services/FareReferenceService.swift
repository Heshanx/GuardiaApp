import Foundation
import Combine

@MainActor
final class FareReferenceService: ObservableObject {
    @Published private(set) var reference: FareReference?
    @Published private(set) var status = "Select an area after previewing a route."
    @Published private(set) var loading = false
    private var generation = 0

    func load(area: String, distance: Double?) async {
        generation += 1
        let token = generation
        reference = nil
        loading = false
        guard ["colombo", "kandy", "galle"].contains(area), let distance,
              let band = FareReference.distanceBand(meters: distance) else {
            status = "Select a fare area and preview a route up to 100 km."
            return
        }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let data = FileManager.default.contents(atPath: path),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values["PROJECT_ID"] as? String == "guardia-a63bd" else {
            status = "Firebase configuration is unavailable."
            return
        }
        let id = "LK_\(area)_tuktuk_\(band)"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/projects/guardia-a63bd/databases/(default)/documents/fareReferences/\(id)") else { return }
        loading = true
        status = "Loading published fare reports…"
        defer { if token == generation { loading = false } }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard token == generation else { return }
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 { status = "No fare record for this area/distance, or the Firestore database is not set up yet."; return }
            if http.statusCode == 403 { status = "Fare data is unavailable. Firestore access needs to be configured."; return }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let document = try JSONDecoder().decode(FirestoreFareDocument.self, from: data)
            guard let value = document.reference(area: area, band: band, now: Date()) else {
                status = "No valid recent reference with at least five reports is available."
                return
            }
            reference = value
            status = "\(value.sampleCount) reports · updated \(value.updatedAt.formatted(date: .abbreviated, time: .omitted))"
        } catch is CancellationError { }
        catch {
            guard token == generation else { return }
            status = "Fare reference could not be loaded. You can still start your trip."
        }
    }
}
