import SwiftUI

struct TripPlanView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var fare = ""
    private var parsedFare: Double? {
        FareValidation.parse(fare, decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }
    private var valid: Bool {
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (fare.isEmpty || (parsedFare != nil && parsedFare! > 0 && parsedFare!.isFinite))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Where to?") { TextField("Enter a destination", text: $destination).textInputAutocapitalization(.words).accessibilityIdentifier("tripDestination") }
                Section {
                    HStack { Text("LKR").foregroundStyle(.secondary); TextField("Agreed fare (optional)", text: $fare).keyboardType(.decimalPad) }
                } header: { Text("Agreed fare") } footer: { Text("Fare references will appear when community data is connected. Your entered fare is saved with this trip.") }
                Section {
                    Label("Verified check-in", systemImage: "faceid")
                    Text("Confirm with Face ID or your device passcode before your trip starts.").foregroundStyle(.secondary)
                    Button { Task { if await store.startTrip(destination: destination, fare: parsedFare) { dismiss() } } } label: {
                        HStack { if store.isAuthenticating { ProgressView() }; Text("Confirm & Start") }
                    }.disabled(!valid || store.isAuthenticating)
                }
            }.navigationTitle("New Trip").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isAuthenticating) } }
        }.interactiveDismissDisabled(store.isAuthenticating)
    }
}
