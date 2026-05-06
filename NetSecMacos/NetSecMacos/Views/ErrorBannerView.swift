import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.ColorToken.warning)

            Text(message)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            Spacer()

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ColorToken.accent)
        }
        .padding(14)
        .background(AppTheme.ColorToken.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous)
                .stroke(AppTheme.ColorToken.warning.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
}
