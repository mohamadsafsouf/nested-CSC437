import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isCreatingAccount = false

    var body: some View {
        HStack(spacing: 44) {
            VStack(alignment: .leading, spacing: 26) {
                LandingAnimationView()
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 10) {
                    Text("CamGuard")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    Text("Monitor camera security metadata across your Mac, detect suspicious behavior, and keep your account protected.")
                        .font(.title3)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 540)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isCreatingAccount ? "Create account" : "Sign in")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    Text("Use your CamGuard account to access protected monitoring.")
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(AppTheme.ColorToken.panelElevated)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(AppTheme.ColorToken.panelElevated)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))

                    if isCreatingAccount {
                        TextField("Display name", text: $displayName)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(AppTheme.ColorToken.panelElevated)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Button {
                    Task {
                        if isCreatingAccount {
                            await session.signUp(email: email, password: password, displayName: displayName)
                        } else {
                            await session.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        Text(session.isAuthenticating ? "Connecting..." : primaryButtonTitle)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: session.isAuthenticating ? "lock.rotation" : "arrow.right")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .foregroundStyle(.black)
                    .background(AppTheme.ColorToken.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(session.isAuthenticating)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCreatingAccount.toggle()
                    }
                } label: {
                    Text(isCreatingAccount ? "Already have an account? Sign in" : "Need an account? Create one")
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
                .buttonStyle(.plain)
                .disabled(session.isAuthenticating)

                Button {
                    Task {
                        await session.resendConfirmation(email: email)
                    }
                } label: {
                    Text("Resend confirmation email")
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(session.isAuthenticating)

                Text("No camera media is collected or uploaded. Only security metadata is used for CamGuard monitoring.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }
            .camGuardPanel()
            .frame(width: 420)
        }
        .padding(44)
    }

    private var primaryButtonTitle: String {
        isCreatingAccount ? "Create account" : "Enter monitoring console"
    }
}

#Preview {
    SignInView()
        .environmentObject(AppSessionStore())
        .background(AppTheme.ColorToken.background)
}
