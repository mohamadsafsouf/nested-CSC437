import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isCreatingAccount = false
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)

                form
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 26)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 34)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            LandingAnimationView()

            Text("CamGuard")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isCreatingAccount ? "Create account" : "Sign in")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .camGuardTextField()

                SecureField("Password", text: $password)
                    .textContentType(isCreatingAccount ? .newPassword : .password)
                    .camGuardTextField()

                if isCreatingAccount {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .camGuardTextField()
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
                .padding(.vertical, 15)
                .foregroundStyle(.black)
                .background(AppTheme.ColorToken.accent)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(session.isAuthenticating)

            VStack(alignment: .leading, spacing: 12) {
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
            }

            Label("No camera media upload.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(AppTheme.ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .camGuardPanel()
    }

    private var primaryButtonTitle: String {
        isCreatingAccount ? "Create account" : "Enter monitoring console"
    }
}

private extension View {
    func camGuardTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(14)
            .foregroundStyle(AppTheme.ColorToken.textPrimary)
            .background(AppTheme.ColorToken.panelElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
    }
}

#Preview {
    SignInView()
        .environmentObject(AppSessionStore())
        .background(AppTheme.ColorToken.background)
}
