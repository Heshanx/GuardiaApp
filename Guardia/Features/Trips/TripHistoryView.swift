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
                            Section("Along the way") {
                                ForEach(route.checkIns ?? []) { check in
                                    VStack(alignment: .leading) {
                                        Text("Route check-in").font(.headline)
                                        Text(check.raisedAt, format: .dateTime)
                                        Text(check.response ?? "Not answered")
                                    }
                                }


                                Text("Blue is your planned route. Green shows where you travelled.").font(.footnote)
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
                            if let fare = trip.agreedFare { LabeledContent("Agreed fare", value: fare.formatted(.currency(code: "LKR").precision(.fractionLength(0)))) }
                            if let paid = trip.paidFare { LabeledContent("Fare paid", value: paid.formatted(.currency(code: "LKR").precision(.fractionLength(0)))) }
                        }
                        Section { Text(trip.route == nil ? "This trip was saved without a route." : "Your journey is saved privately on this device.").foregroundStyle(.secondary) }
                    }.guardiaSurface(width: 900).navigationTitle("Trip details")
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
            }.guardiaSurface().navigationTitle("Trips").overlay {
                if store.trips.isEmpty { ContentUnavailableView("No trips yet", systemImage: "clock", description: Text("Trips you take with Guardia will appear here.")) }
            }
        }
    }
    private func duration(from start: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        return "\(seconds / 60) min \(seconds % 60) sec"
    }
}
