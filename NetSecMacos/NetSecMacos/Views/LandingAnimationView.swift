import SwiftUI

struct LandingAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var orbit = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(AppTheme.ColorToken.accent.opacity(0.18), lineWidth: 1)
                    .frame(width: CGFloat(160 + index * 54), height: CGFloat(160 + index * 54))
                    .scaleEffect(pulse ? 1.06 : 0.94)
                    .opacity(pulse ? 0.35 : 0.90)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.8 + Double(index) * 0.25).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.ColorToken.accent.opacity(0.32),
                            AppTheme.ColorToken.panel.opacity(0.4),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)

            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .shadow(color: AppTheme.ColorToken.accent.opacity(0.45), radius: 24)

            Image(systemName: "shield.checkered")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .offset(y: -122)
                .rotationEffect(.degrees(orbit ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 10).repeatForever(autoreverses: false), value: orbit)
        }
        .frame(width: 360, height: 360)
        .onAppear {
            pulse = true
            orbit = true
        }
    }
}

#Preview {
    LandingAnimationView()
        .frame(width: 500, height: 500)
        .background(AppTheme.ColorToken.background)
}
