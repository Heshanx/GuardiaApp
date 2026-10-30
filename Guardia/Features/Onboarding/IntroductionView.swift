import SwiftUI

struct IntroductionView: View {
    @ObservedObject var store: GuardiaStore
    @AppStorage("completedIntroduction") private var complete = false
    @AppStorage("introductionStep") private var step = 0
    @State private var notificationStatus: String?
    var body: some View {
        VStack(spacing: 0) {
            if step == 0 {
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 64)).foregroundStyle(GuardiaStyle.accent).padding(.top, 64)
                        Text("Guardia").font(.largeTitle.bold())
                        Text("Calm support for every street ride.").font(.title3).multilineTextAlignment(.center)
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 92, weight: .ultraLight)).foregroundStyle(GuardiaStyle.accent.opacity(0.4)).padding(40).accessibilityHidden(true)
                    }.padding(28)
                }
            } else if step == 1 { ContactsView(store: store) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("A few permissions").font(.largeTitle.bold())
                        Text("Choose what helps keep your ride connected and private.").foregroundStyle(.secondary)
                        permission("Face ID", icon: "faceid", detail: "Confirms it’s you before a trip starts. Your device passcode remains available.")
                        permission("Location", icon: "location", detail: "Records your route during an active trip, including while your screen is locked.")
                        Button("Allow location access") { store.location.beginPreview() }
                        permission("Notifications", icon: "bell", detail: "A quiet prompt asks you to review a route check-in.")
                        Button("Allow notifications") {
                            Task {
                                do { notificationStatus = try await store.notifications.requestPermission() ? "Notifications allowed" : "You can enable notifications later in Settings." }
                                catch { notificationStatus = error.localizedDescription }
                            }
                        }
                        if let notificationStatus { Text(notificationStatus).font(.footnote).foregroundStyle(.secondary) }
                        Text("Contact alerts and community fare comparisons are not connected yet.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(28).frame(maxWidth: 620)
                }
            }
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.padding(.trailing) }
                Button(step == 0 ? "Get Started" : step == 1 ? "Continue" : "Finish setup") {
                    if step < 2 { step += 1 } else { store.location.endPreview(); complete = true }
                }.buttonStyle(GuardiaPrimaryButton())
            }.padding(24).frame(maxWidth: 620)
        }.frame(maxWidth: .infinity).background(GuardiaStyle.background)
            .onDisappear { store.location.endPreview() }
    }
    private func permission(_ title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(GuardiaStyle.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary) }
        }
    }
}
