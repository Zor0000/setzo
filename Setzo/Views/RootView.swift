import AuthenticationServices
import CryptoKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            NativeBackground()
            if let storageError = app.storageError {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.accent)
                    Text("Saved data needs attention")
                        .font(.system(size: 24, weight: .bold))
                    Text(storageError)
                        .multilineTextAlignment(.center)
                    Text("Free up storage if needed, then retry. If the saved data requires a newer app version, update Setzo first.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted2)
                    Button("Retry") { Task { await app.retryStorage() } }
                        .disabled(app.isRetryingStorage)
                        .accessibilityIdentifier("retry-storage-button")
                    Link("Contact support", destination: URL(string: "mailto:neerajchormale39@gmail.com")!)
                }
                .padding(28)
            } else if app.isBooting {
                SwiftUI.ProgressView("Opening Setzo…")
                    .tint(Theme.accent)
            } else if app.showingOnboarding {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else if app.showingAuth {
                AuthView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                AppShellView()
                    .transition(.opacity.combined(with: .scale(scale: 0.995)))
            }
            if let toast = app.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                        .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
                        .padding(.bottom, 72)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.success, trigger: app.toast)
        .animation(AppMotion.smooth, value: app.toast)
        .animation(AppMotion.screen, value: app.showingAuth)
        .animation(AppMotion.screen, value: app.showingOnboarding)
        .alert("Remove Setzo from Apple sign-in", isPresented: Binding(
            get: { app.showAppleRevocationInstructions && !app.showingSettings },
            set: { app.showAppleRevocationInstructions = $0 }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your Setzo account has been deleted. To remove Apple's remaining authorization, open iPhone Settings → your name → Sign in with Apple → Setzo → Delete or Stop Using Apple ID. You can also do this at account.apple.com under Sign-In and Security → Sign in with Apple.")
        }
        .alert("Finish account deletion?", isPresented: $app.needsDeletionReconfirmation) {
            Button("Delete Account & Data", role: .destructive) {
                Task { _ = await app.deleteAccount() }
            }
            Button("Keep Account", role: .cancel) { app.cancelPendingDeletionRequest() }
        } message: {
            Text("Your session expired before deletion. You have signed in again; confirm to delete this account and its data.")
        }
        .alert("Remove Apple access manually?", isPresented: Binding(
            get: { app.needsAppleRevocationFallback && !app.showingSettings },
            set: { app.needsAppleRevocationFallback = $0 }
        )) {
            Button("Delete Account & Data", role: .destructive) {
                Task { _ = await app.deleteAccount(allowManualAppleRevocation: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Automatic Apple revocation is unavailable. You can still delete your Setzo account and data. Then open iPhone Settings → your name → Sign in with Apple → Setzo and stop using Sign in with Apple.")
        }
    }
}

/// First-run intro: three swipeable cards ending in the cloud-vs-local choice.
/// Shown once (gated on `hasOnboarded` in the snapshot), always skippable.
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var page = 0

    private let cards: [(icon: String, title: String, text: String)] = [
        ("dumbbell.fill", "Log sets in seconds",
         "Pick a split, tap through your exercises, check off sets as you lift. No clutter, no subscription."),
        ("timer", "Rest runs itself",
         "Finishing a set starts your rest timer. Log the next set right from the Lock Screen — and get pinged when rest is over."),
        ("chart.line.uptrend.xyaxis", "Watch the bar go up",
         "PRs are detected automatically and every exercise gets a progress graph. Your data stays yours."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    NativeFeedback.selection()
                    app.finishOnboarding(createAccount: false)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .accessibilityIdentifier("onboarding-skip-button")
            }

            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    VStack(spacing: 18) {
                        Image(systemName: card.icon)
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.accent)
                        Text(card.title)
                            .font(.system(size: 30, weight: .black))
                            .fontWidth(.condensed)
                        Text(card.text)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 9) {
                if page < cards.count - 1 {
                    Button {
                        NativeFeedback.light()
                        withAnimation(AppMotion.smooth) { page += 1 }
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        NativeFeedback.light()
                        app.finishOnboarding(createAccount: true)
                    } label: {
                        Label("Create Account — Sync Everywhere", systemImage: "icloud")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        NativeFeedback.selection()
                        app.finishOnboarding(createAccount: false)
                    } label: {
                        Text("Continue locally — no account needed")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("onboarding-continue-locally-button")
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
            .animation(AppMotion.quick, value: page)
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showForgotPassword = false
    @State private var isAdult = false
    @State private var appleNonce: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 4) {
                Text(app.isPasswordRecovery ? "New password" : "Setzo")
                    .font(.system(size: 52, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(app.isPasswordRecovery ? 0 : 4)
                    .foregroundStyle(Theme.accent)
                Text(app.isPasswordRecovery
                     ? "Choose a new password for your account."
                     : "Track your gains. Own your progress.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted2)
            }

            VStack(spacing: 14) {
                if app.isPasswordRecovery {
                    passwordRecoveryForm
                } else {
                    Picker("", selection: $mode) {
                        Text("Sign In").tag(AuthMode.signIn)
                        Text("Sign Up").tag(AuthMode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                    .animation(AppMotion.quick, value: mode)
                    .disabled(app.isBusy)

                    authMessage

                    if mode == .signUp {
                        TextField("", text: $name)
                            .textContentType(.name)
                            .fieldStyle()
                            .placeholderText("Your name", visible: name.isEmpty)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                        .placeholderText("Email address", visible: email.isEmpty)
                    SecureField("", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .fieldStyle()
                        .placeholderText(mode == .signIn ? "Password" : "Password (8+ characters)", visible: password.isEmpty)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            app.authMessage = nil
                            showForgotPassword = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(app.isBusy)
                        .accessibilityIdentifier("forgot-password-button")
                    } else {
                        Text("Use at least 8 characters.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle("I am 18 or older (required to create an account)", isOn: $isAdult)
                        .font(.system(size: 12))
                        .tint(Theme.accent)
                        .accessibilityIdentifier("account-age-confirmation")

                    Button {
                        NativeFeedback.light()
                        Task {
                            if mode == .signIn {
                                await app.signIn(email: cleanEmail, password: password)
                            } else {
                                let shouldShowSignIn = await app.signUp(
                                    email: cleanEmail,
                                    password: password,
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                                if shouldShowSignIn { mode = .signIn }
                            }
                        }
                    } label: {
                        busyLabel(authButtonTitle, darkSpinner: true)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)

                    HStack(spacing: 12) {
                        Rectangle().fill(Theme.border).frame(height: 1)
                        Text("OR")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted2)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }

                    Button {
                        NativeFeedback.light()
                        // Sign-in with an existing account never requires the
                        // age toggle — only account creation does. Keeping the
                        // button tappable here is what keeps App Review (and
                        // every returning user) from seeing a dead button.
                        if mode == .signUp && !isAdult {
                            app.authMessage = "Please confirm you are 18 or older to create an account."
                            return
                        }
                        Task { await app.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text("Continue with Google")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.isBusy || (mode == .signUp && !isAdult))
                    .accessibilityIdentifier("google-sign-in-button")

                    SignInWithAppleButton(.signIn) { request in
                        let nonce = UUID().uuidString
                        appleNonce = nonce
                        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        // Same rule as Google: returning users sign straight
                        // in; the age check only gates new accounts.
                        if mode == .signUp && !isAdult {
                            app.authMessage = "Please confirm you are 18 or older to create an account."
                            appleNonce = nil
                            return
                        }
                        let nonce = appleNonce
                        appleNonce = nil
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let tokenData = credential.identityToken,
                                  let idToken = String(data: tokenData, encoding: .utf8),
                                  let nonce else {
                                app.authMessage = "Apple sign-in did not return a valid identity. Try again."
                                return
                            }
                            Task {
                                await app.signInWithApple(
                                    idToken: idToken,
                                    nonce: nonce,
                                    fullName: credential.fullName?.formatted()
                                )
                            }
                        case .failure(let error):
                            if (error as? ASAuthorizationError)?.code != .canceled {
                                app.authMessage = error.localizedDescription
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .disabled(app.isBusy || (mode == .signUp && !isAdult))
                    .accessibilityIdentifier("apple-sign-in-button")

                    VStack(spacing: 4) {
                        Text("Accounts and social sign-in are for adults 18+. Under-18s can use local workouts with a parent or guardian; Fuel Buddy is unavailable.")
                            .multilineTextAlignment(.center)
                        Text("Before creating an account, read:")
                        HStack(spacing: 12) {
                            Link("Privacy Policy", destination: URL(string: "https://www.neeraj.works/setzo/privacy.html")!)
                            Link("Terms of Use", destination: URL(string: "https://www.neeraj.works/setzo/terms.html")!)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted2)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("auth-privacy-policy")

                    Button {
                        NativeFeedback.selection()
                        app.continueLocally()
                    } label: {
                        Text("Continue locally")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.isBusy)
                }
            }
            .cardStyle(radius: 18)
            .padding(.horizontal, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .entrance()
            Spacer()
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: cleanEmail)
                .environmentObject(app)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var authMessage: some View {
        if let message = app.authMessage {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(isPositiveMessage(message) ? Theme.success : Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("auth-message")
        }
    }

    private var passwordRecoveryForm: some View {
        VStack(spacing: 14) {
            authMessage
            SecureField("", text: $password)
                .textContentType(.newPassword)
                .fieldStyle()
                .placeholderText("New password", visible: password.isEmpty)
            SecureField("", text: $confirmation)
                .textContentType(.newPassword)
                .fieldStyle()
                .placeholderText("Confirm new password", visible: confirmation.isEmpty)
            Text(password.count >= 8 && confirmation != password
                 ? "Passwords do not match."
                 : "Use at least 8 characters.")
                .font(.system(size: 12))
                .foregroundStyle(password.count >= 8 && confirmation != password ? Theme.danger : Theme.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NativeFeedback.light()
                Task { await app.completePasswordReset(password) }
            } label: {
                busyLabel(app.isBusy ? "Updating…" : "Update Password", darkSpinner: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(app.isBusy || password.count < 8 || password != confirmation)
            .accessibilityIdentifier("update-password-button")
        }
    }

    private func busyLabel(_ title: String, darkSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if app.isBusy {
                SwiftUI.ProgressView().tint(darkSpinner ? .black : Theme.text)
            }
            Text(title)
        }
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !app.isBusy,
              !cleanEmail.isEmpty,
              !password.isEmpty else { return false }
        if mode == .signUp {
            return isAdult && password.count >= 8 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var authButtonTitle: String {
        if app.isBusy {
            return mode == .signIn ? "Signing In…" : "Creating Account…"
        }
        return mode == .signIn ? "Sign In" : "Create Account"
    }

    private func isPositiveMessage(_ message: String) -> Bool {
        message.contains("created") || message.contains("reset link")
    }

}

private struct ForgotPasswordView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var sent = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ZStack {
            NativeBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset password")
                    .font(.system(size: 30, weight: .black))
                    .fontWidth(.condensed)
                Text(sent
                     ? "If an account exists for that email, a reset link is on its way."
                     : "Enter your account email and we’ll send you a secure reset link.")
                    .font(.system(size: 13))
                    .foregroundStyle(sent ? Theme.success : Theme.muted2)

                if !sent {
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                        .placeholderText("Email address", visible: email.isEmpty)
                    if let message = app.authMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                    }
                    Button {
                        Task {
                            sent = await app.requestPasswordReset(
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if app.isBusy { SwiftUI.ProgressView().tint(.black) }
                            Text(app.isBusy ? "Sending…" : "Send Reset Link")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(app.isBusy || !email.contains("@"))
                    .accessibilityIdentifier("send-reset-link-button")
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(28)
        }
        .onAppear { app.authMessage = nil }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var app: AppState
    @Namespace private var tabSelection

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $app.selectedTab) {
                WorkoutsView().tag(WorkoutTab.workouts)
                LogView().tag(WorkoutTab.log)
                RunView().tag(WorkoutTab.run)
                ProgressView().tag(WorkoutTab.progress)
                IronFuelView().tag(WorkoutTab.ironFuel)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppMotion.screen, value: app.selectedTab)

            HStack {
                navButton(.workouts, "Workouts", "list.bullet")
                navButton(.log, "Today", "timer")
                navButton(.run, "Run", "figure.run")
                navButton(.progress, "Progress", "chart.line.uptrend.xyaxis")
                navButton(.ironFuel, "IronFuel", "fork.knife")
            }
            .padding(.horizontal, 6)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .background {
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.035), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
        }
    }

    private var header: some View {
        HStack {
            Text("Setzo")
                .font(.system(size: 28, weight: .black))
                .fontWidth(.condensed)
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 13, weight: .bold))
                Text(Date().formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            }
            Button {
                NativeFeedback.selection()
                app.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted2)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
            .sheet(isPresented: $app.showingSettings) {
                SettingsView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(Theme.surface.opacity(0.96))
                .overlay {
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
    }

    private func navButton(_ tab: WorkoutTab, _ label: String, _ icon: String) -> some View {
        let isActive = app.selectedTab == tab
        return Button {
            NativeFeedback.selection()
            withAnimation(AppMotion.quick) {
                app.selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .scaleEffect(isActive ? 1.08 : 1)
                    .symbolEffect(.bounce, value: isActive)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accentDim)
                        .matchedGeometryEffect(id: "tabSelection", in: tabSelection)
                }
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("main-tab-\(label.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

extension View {
    func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(13)
            .foregroundStyle(Theme.text)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    /// Legible placeholder overlay — the system placeholder is nearly invisible on the dark
    /// surface. Pass "" to the field itself and drive `visible` off its emptiness. Apply after
    /// `fieldStyle()` so the 13pt inset lines up with the field's text.
    func placeholderText(_ text: String, visible: Bool) -> some View {
        overlay(alignment: .leading) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted2)
                .padding(.horizontal, 13)
                .allowsHitTesting(false)
                .opacity(visible ? 1 : 0)
        }
    }
}
