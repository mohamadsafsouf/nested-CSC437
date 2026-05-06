import SwiftUI

struct AnimatedBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            AppTheme.ColorToken.background

            Circle()
                .fill(AppTheme.ColorToken.accent.opacity(0.20))
                .blur(radius: 70)
                .frame(width: 260, height: 260)
                .offset(x: drift ? 140 : -80, y: drift ? -240 : -160)

            Circle()
                .fill(AppTheme.ColorToken.cyan.opacity(0.16))
                .blur(radius: 82)
                .frame(width: 320, height: 320)
                .offset(x: drift ? -150 : 120, y: drift ? 260 : 180)

            LinearGradient(
                colors: [.clear, AppTheme.ColorToken.panel.opacity(0.24), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .rotationEffect(.degrees(drift ? 8 : -8))
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 7).repeatForever(autoreverses: true), value: drift)
        .onAppear {
            drift = true
        }
    }
}
