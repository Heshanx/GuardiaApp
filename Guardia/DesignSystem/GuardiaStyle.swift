import SwiftUI

enum GuardiaStyle {
    static let buttonBlue = Color(red: 0.19, green: 0.33, blue: 0.59)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.44, green: 0.69, blue: 1, alpha: 1) : UIColor(red: 0.19, green: 0.33, blue: 0.59, alpha: 1)
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.systemGroupedBackground : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)
    })
}

struct GuardiaCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct GuardiaPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(.white).background(GuardiaStyle.buttonBlue, in: RoundedRectangle(cornerRadius: 14))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

/// Constrain reading width within the current window, including iPad Split View.
private struct GuardiaSurface: ViewModifier {
    var width: CGFloat
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .frame(maxWidth: width).frame(maxWidth: .infinity)
            .background(GuardiaStyle.background)
    }
}
extension View {
    func guardiaSurface(width: CGFloat = 800) -> some View { modifier(GuardiaSurface(width: width)) }
}
