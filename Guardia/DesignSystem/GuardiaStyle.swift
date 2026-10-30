import SwiftUI

enum GuardiaStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.44, green: 0.69, blue: 1, alpha: 1) : UIColor(red: 0.14, green: 0.32, blue: 0.64, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
}

struct GuardiaCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.06)))
    }
}
