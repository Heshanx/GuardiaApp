import SwiftUI

struct TripHistoryView: View {
    @ObservedObject var store: GuardiaStore
    var body: some View {
        NavigationStack {
            List(store.trips) { trip in
                NavigationLink {
                    Form {
                        if let route = trip.route {
                            Section { TripRouteMap(route: route) }
                            Section("Route recording") {
                                ForEach(route.checkIns ?? []) { check in
                                    VStack(alignment: .leading) {
                                        Text("Route check-in").font(.headline)
                                        Text(check.raisedAt, format: .dateTime)
                                        Text(check.response ?? "Not answered")
                                    }
                                }
                                LabeledContent("Location points", value: "\(route.samples.count)")
                                LabeledContent("Recording sessions", value: "\(route.recordingSessions.count)")
                                Text("Blue shows the planned route; green shows recorded positions. Gaps over two minutes are not joined.").font(.footnote)
                            }
                        }
                        Section("Destination") { Text(trip.destination).font(.title2.bold()) }
                        Section("Trip details") {
                            LabeledContent("Status", value: trip.status.rawValue.capitalized)
                            LabeledContent("Started", value: trip.startedAt.formatted())
                            if let end = trip.endedAt {
                                LabeledContent("Ended", value: end.formatted())
                                LabeledContent("Duration", value: duration(from: trip.startedAt, to: end))
                            }
                            if let fare = trip.agreedFare { LabeledContent("Agreed fare", value: fare.formatted(.currency(code: "LKR"))) }
                        }
                        Section { Text(trip.route == nil ? "This trip contains check-in details only. Route recording and alerts were not enabled." : "Route data and check-in responses stay on this device. Contact alerts are not connected.").foregroundStyle(.secondary) }
                    }.navigationTitle("Trip details")
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: trip.status == .active ? "location.fill" : "mappin.and.ellipse").foregroundStyle(GuardiaStyle.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.destination).font(.headline)
                            Text(trip.startedAt, format: .dateTime.day().month().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                            Text(trip.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
            }.navigationTitle("Trips").overlay {
                if store.trips.isEmpty { ContentUnavailableView("No trips yet", systemImage: "clock", description: Text("Trips you take with Guardia will appear here.")) }
            }
        }
    }
    private func duration(from start: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        return "\(seconds / 60) min \(seconds % 60) sec"
    }
}
