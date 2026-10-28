import SwiftUI

enum GuardiaStyle {
    static let accent = Color(red: 0.19, green: 0.33, blue: 0.58)
    static let background = Color(uiColor: .systemGroupedBackground)
}

struct GuardiaCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
