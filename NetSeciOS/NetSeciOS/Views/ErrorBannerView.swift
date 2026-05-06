import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.ColorToken.warning)

            Text(message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.ColorToken.panelElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.ColorToken.panel.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}
