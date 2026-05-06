import SwiftUI

struct LandingAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var orbit = false
    @State private var scan = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(AppTheme.ColorToken.accent.opacity(0.18), lineWidth: 1)
                    .frame(width: CGFloat(140 + index * 48), height: CGFloat(140 + index * 48))
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.30 : 0.90)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.7 + Double(index) * 0.22).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.ColorToken.accent.opacity(0.34),
                            AppTheme.ColorToken.panel.opacity(0.48),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 138
                    )
                )
                .frame(width: 276, height: 276)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.ColorToken.cyan.opacity(0.35), lineWidth: 1)
                .frame(width: 118, height: 166)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(AppTheme.ColorToken.textSecondary.opacity(0.45))
                        .frame(width: 38, height: 5)
                        .padding(.top, 12)
                }
                .shadow(color: AppTheme.ColorToken.accent.opacity(0.28), radius: 24)

            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .shadow(color: AppTheme.ColorToken.accent.opacity(0.45), radius: 24)

            Rectangle()
                .fill(AppTheme.ColorToken.accent.opacity(0.36))
                .frame(width: 120, height: 2)
                .offset(y: scan ? 58 : -58)
                .blur(radius: 1.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: scan)

            Image(systemName: "shield.checkered")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .offset(y: -112)
                .rotationEffect(.degrees(orbit ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 10).repeatForever(autoreverses: false), value: orbit)
        }
        .frame(width: 320, height: 320)
        .onAppear {
            pulse = true
            orbit = true
            scan = true
        }
    }
}

#Preview {
    LandingAnimationView()
        .background(AppTheme.ColorToken.background)
}
