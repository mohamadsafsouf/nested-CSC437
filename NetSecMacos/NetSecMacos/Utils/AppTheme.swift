import SwiftUI

enum AppTheme {
    enum ColorToken {
        static let background = Color(red: 0.01, green: 0.02, blue: 0.06)
        static let panel = Color(red: 0.06, green: 0.09, blue: 0.16)
        static let panelElevated = Color(red: 0.10, green: 0.14, blue: 0.22)
        static let textPrimary = Color(red: 0.97, green: 0.98, blue: 0.99)
        static let textSecondary = Color(red: 0.58, green: 0.64, blue: 0.72)
        static let accent = Color(red: 0.13, green: 0.77, blue: 0.37)
        static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
        static let critical = Color(red: 0.94, green: 0.27, blue: 0.27)
        static let border = Color.white.opacity(0.10)
    }

    enum Layout {
        static let cornerRadius: CGFloat = 22
        static let compactCornerRadius: CGFloat = 14
        static let contentMaxWidth: CGFloat = 1180
    }
}

extension View {
    func camGuardPanel() -> some View {
        self
            .padding(20)
            .background(AppTheme.ColorToken.panel.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Layout.cornerRadius, style: .continuous)
                    .stroke(AppTheme.ColorToken.border, lineWidth: 1)
            )
    }
}
