import SwiftUI
import SwiftData
import UIKit

// MARK: - Sign In Initial Mode

enum SignInInitialMode {
    case signIn
    case createAccount
}

// MARK: - Password Strength

enum PasswordStrength {
    case weak
    case medium
    case strong
    
    var color: Color {
        switch self {
        case .weak: return .red
        case .medium: return .orange
        case .strong: return .green
        }
    }
    
    var message: String {
        switch self {
        case .weak: return "Weak password"
        case .medium: return "Good password"
        case .strong: return "Strong password"
        }
    }
}

struct SignInView: View {
    @ObservedObject var authService: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // F-6 (FR-27, identity-epoch rule): the create-account flow asks the neutral age
    // question at its start whenever the current identity epoch has no answer. Because
    // sign-out/deletion clear the epoch, a resolved answer here always belongs to THIS
    // identity (e.g. just given at the first-launch or rebirth gate) and is reused
    // instead of asking twice in a row; a previous account's answer can never carry
    // over (incident-2 regression).
    @ObservedObject private var ageGateStore = AgeGateStore.shared

    @State private var isSignInMode: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var userName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var passwordMatchError: String? = nil
    @State private var passwordMatchTask: Task<Void, Never>? = nil
    @State private var accountStateAtAppear: AccountState = .localGuest
    @State private var didReportAuthSuccess = false
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    /// FR-27 (flow-scoped): the age step answered within THIS presentation.
    @State private var hasAnsweredAgeThisFlow = false

    var onAuthSuccess: (() -> Void)?
    var deferredSetupTouchSource: String = "profile"

    init(
        authService: FirebaseAuthService,
        initialMode: SignInInitialMode = .signIn,
        deferredSetupTouchSource: String = "profile",
        onAuthSuccess: (() -> Void)? = nil
    ) {
        self.authService = authService
        self.deferredSetupTouchSource = deferredSetupTouchSource
        self._isSignInMode = State(initialValue: initialMode == .signIn)
        self._email = State(initialValue: "")
        self._password = State(initialValue: "")
        self._confirmPassword = State(initialValue: "")
        self._userName = State(initialValue: "")
        self._showError = State(initialValue: false)
        self._errorMessage = State(initialValue: "")
        self._isLoading = State(initialValue: false)
        self._passwordMatchError = State(initialValue: nil)
        self._passwordMatchTask = State(initialValue: nil)
        self._showPassword = State(initialValue: false)
        self._showConfirmPassword = State(initialValue: false)
        self.onAuthSuccess = onAuthSuccess
    }

    private var isCreateModeAwaitingAgeAnswer: Bool {
        !isSignInMode && !hasAnsweredAgeThisFlow && !ageGateStore.isResolved
    }

    /// COPPA F-18 (FR-60(e)): an under-13 epoch has no account to create. Registration
    /// collected the child's own email and password, which is online contact information
    /// under §312.2 — collecting it BEFORE a parent has consented was itself the violation,
    /// and the previous advisory note left the fields live beside it. Under the local-first
    /// model there is nothing to replace it with: the child already has everything they need
    /// locally, so create-mode offers exactly the two things FR-60(e) names — keep playing
    /// here, or join a family with a share code.
    private var isCreateModeForChild: Bool {
        !isSignInMode && ageGateStore.category == .under13
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if isCreateModeAwaitingAgeAnswer {
                    // FR-27: the age question starts every create-account flow, fresh.
                    AgeGateView(source: .registration) {
                        hasAnsweredAgeThisFlow = true
                    }
                } else if isCreateModeForChild {
                    ChildAccountCreationGuidanceView(
                        authService: authService,
                        onKeepPlaying: { dismiss() },
                        onSwitchToSignIn: {
                            withAnimation {
                                password = ""
                                confirmPassword = ""
                                userName = ""
                                showPassword = false
                                showConfirmPassword = false
                                isSignInMode = true
                            }
                        }
                    )
                } else {
                    signInScrollContent
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                accountStateAtAppear = currentAccountState()
                DeferredProfileSetupStore.shared.markTouched(.account, source: deferredSetupTouchSource)
            }
            .onChange(of: authService.currentUser?.email) { _, _ in
                evaluateAccountStateTransition()
            }
            .onChange(of: authService.currentUser?.firebaseUID ?? authService.currentUser?.id) { _, _ in
                evaluateAccountStateTransition()
            }
            .onDisappear {
                // Cancel any pending password match check when view disappears
                passwordMatchTask?.cancel()
            }
        }
    }

    private var signInScrollContent: some View {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text(isSignInMode ? "Sign In" : "Create Account")
                                .font(.system(.largeTitle, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            Text(isSignInMode ? "Sign in to sync your data across devices" : "Create an account to save your progress")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 32)
                        .padding(.bottom, 8)
                        
                        // Form
                        VStack(spacing: 20) {
                            if !isSignInMode {
                                // Username field (only for create account)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Username")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    TextField("Choose a username", text: $userName)
                                        // Display name — keep .username for the email field so Strong Password pairs correctly.
                                        .textContentType(.nickname)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .autocapitalization(.none)
                                }

                                // No name fields: real names are never collected
                                // (owner decision, F-6 rework; FR-52 satisfied for all).
                                //
                                // COPPA F-18 (FR-60(e)): the under-13 advisory note that used
                                // to sit here is gone with the form it annotated — an under-13
                                // epoch never reaches this branch now (`isCreateModeForChild`).
                            }
                            
                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                TextField("Enter your email", text: $email)
                                    // Create: .username pairs with .newPassword for Strong Password.
                                    // Sign In: keep .emailAddress to avoid unrelated AutoFill churn.
                                    .textContentType(isSignInMode ? .emailAddress : .username)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .rounded))
                                    .autocapitalization(.none)
                            }
                            
                            // Password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                ZStack(alignment: .trailing) {
                                    if isSignInMode {
                                        SignInPasswordField(
                                            text: $password,
                                            isVisible: showPassword,
                                            placeholder: "Enter your password"
                                        )
                                    } else {
                                        NewPasswordAutoFillField(
                                            text: $password,
                                            isVisible: showPassword,
                                            placeholder: "Enter your password",
                                            trailingContentInset: 44
                                        )
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                    }
                                    
                                    PasswordVisibilityToggle(isVisible: $showPassword)
                                        .padding(.trailing, 2)
                                }
                                
                                // Password strength indicator (only for create account)
                                if !isSignInMode && !password.isEmpty {
                                    passwordStrengthIndicator
                                } else if !isSignInMode {
                                    // Show requirements hint when field is empty
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Password must contain:")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                        Text("• At least 8 characters")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                        Text("• Uppercase and lowercase letters")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                        Text("• At least one number")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                        Text("• Special characters are optional but recommended")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            
                            if !isSignInMode {
                                // Confirm password field (only for create account)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Confirm Password")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    ZStack(alignment: .trailing) {
                                        NewPasswordAutoFillField(
                                            text: $confirmPassword,
                                            isVisible: showConfirmPassword,
                                            placeholder: "Confirm your password",
                                            trailingContentInset: 44
                                        )
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        
                                        PasswordVisibilityToggle(isVisible: $showConfirmPassword)
                                            .padding(.trailing, 2)
                                    }
                                    
                                    // Password match error with debounce
                                    if let matchError = passwordMatchError {
                                        Text(matchError)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.red)
                                            .padding(.top, 4)
                                    }
                                }
                                .onChange(of: password) { _, _ in
                                    checkPasswordMatchDebounced()
                                }
                                .onChange(of: confirmPassword) { _, _ in
                                    checkPasswordMatchDebounced()
                                }
                            }
                            
                            // Submit button
                            Button {
                                if isSignInMode {
                                    signIn()
                                } else {
                                    createAccount()
                                }
                            } label: {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(isSignInMode ? "Sign In" : "Create Account")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(Color.Theme.primaryBlue)
                                )
                                .foregroundStyle(.white)
                            }
                            .disabled(isLoading || !isFormValid)
                            .opacity(isFormValid ? 1.0 : 0.6)
                            .padding(.top, 8)
                            
                            // Toggle between sign in and create account
                            Button {
                                withAnimation {
                                    if isSignInMode {
                                        // Switching to create account - clear password fields first, then autofill
                                        password = ""
                                        confirmPassword = ""
                                        email = ""
                                        if let currentUser = authService.currentUser {
                                            userName = currentUser.userName
                                        }
                                    } else {
                                        // Switching to sign in - clear all fields
                                        password = ""
                                        confirmPassword = ""
                                        userName = ""
                                    }
                                    showPassword = false
                                    showConfirmPassword = false
                                    isSignInMode.toggle()
                                }
                            } label: {
                                Text(isSignInMode ? "Don't have an account? Create one" : "Already have an account? Sign in")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                        .padding(.horizontal, 20)
                        
                        // MVP: OAuth / linked-account sign-in hidden — restore post-MVP
                        /*
                        // OAuth providers
                        VStack(spacing: 16) {
                            Text("Or sign in with")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            
                            VStack(spacing: 12) {
                                // Google Sign In
                                OAuthButton(
                                    title: "Continue with Google",
                                    icon: "globe",
                                    color: Color(red: 0.26, green: 0.52, blue: 0.96)
                                ) {
                                    signInWithGoogle()
                                }
                                
                                // Apple Sign In
                                OAuthButton(
                                    title: "Continue with Apple",
                                    icon: "applelogo",
                                    color: .black
                                ) {
                                    signInWithApple()
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        */
                        
                        // Offline notice
                        if !authService.isOnline {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(.caption, design: .rounded))
                                Text("You're offline. Sign in will work when you're back online.")
                                    .font(.system(.caption, design: .rounded))
                            }
                            .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 32)
                }
    }

    private var isFormValid: Bool {
        if isSignInMode {
            return !email.isEmpty && !password.isEmpty
        } else {
            // For create account, check basic requirements
            // Full validation happens in createAccount()
            let basicValid = !userName.isEmpty &&
                           !email.isEmpty &&
                           !password.isEmpty &&
                           password == confirmPassword &&
                           password.count >= 8
            return basicValid
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        userName = ""
        errorMessage = ""
        showPassword = false
        showConfirmPassword = false
    }

    private func currentAccountState() -> AccountState {
        FirebaseAccountStateProvider.shared.currentAccountState(for: authService.currentUser)
    }

    private func completeAuthSuccess() {
        guard !didReportAuthSuccess else { return }
        didReportAuthSuccess = true
        onAuthSuccess?()
        authService.showSignInSheet = false
        dismiss()
    }

    private func evaluateAccountStateTransition() {
        guard AccountState.shouldReportAuthSuccess(
            from: accountStateAtAppear,
            to: currentAccountState()
        ) else { return }
        completeAuthSuccess()
    }
    
    private func signIn() {
        guard isFormValid else { return }
        
        isLoading = true
        Task {
            do {
                try await authService.signIn(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    completeAuthSuccess()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func createAccount() {
        guard isFormValid else { return }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        // Validate password with security requirements
        let validation = validatePassword(password)
        guard validation.isValid else {
            errorMessage = validation.errorMessage ?? "Password does not meet security requirements"
            showError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.createAccount(
                    email: email,
                    password: password,
                    userName: userName
                )
                await MainActor.run {
                    isLoading = false
                    completeAuthSuccess()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func signInWithGoogle() {
        guard authService.isOnline else {
            errorMessage = "You're offline. Please connect to the internet to sign in with Google."
            showError = true
            return
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to present Google Sign In"
            showError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.signInWithGoogle(presentingViewController: rootViewController)
                await MainActor.run {
                    isLoading = false
                    completeAuthSuccess()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func signInWithApple() {
        guard authService.isOnline else {
            errorMessage = "You're offline. Please connect to the internet to sign in with Apple."
            showError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.signInWithApple()
                await MainActor.run {
                    isLoading = false
                    completeAuthSuccess()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Password Strength Indicator
    
    @ViewBuilder
    private var passwordStrengthIndicator: some View {
        let validation = validatePassword(password)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(validation.strength.color)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                Text(validation.strength.message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(validation.strength.color)
            }
            
            // Password requirements checklist
            VStack(alignment: .leading, spacing: 2) {
                PasswordRequirement(
                    text: "At least 8 characters",
                    isMet: password.count >= 8
                )
                PasswordRequirement(
                    text: "Contains uppercase letter",
                    isMet: password.rangeOfCharacter(from: .uppercaseLetters) != nil
                )
                PasswordRequirement(
                    text: "Contains lowercase letter",
                    isMet: password.rangeOfCharacter(from: .lowercaseLetters) != nil
                )
                PasswordRequirement(
                    text: "Contains number",
                    isMet: password.rangeOfCharacter(from: .decimalDigits) != nil
                )
            }
            .padding(.top, 4)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Password Match Check (Debounced)
    
    private func checkPasswordMatchDebounced() {
        // Cancel any existing task
        passwordMatchTask?.cancel()
        
        // Only check if both fields have content
        guard !password.isEmpty && !confirmPassword.isEmpty else {
            passwordMatchError = nil
            return
        }
        
        // Create a new debounced task
        passwordMatchTask = Task {
            // Wait 0.5 seconds before checking
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Check if passwords match
            await MainActor.run {
                if password != confirmPassword {
                    passwordMatchError = "Passwords do not match"
                } else {
                    passwordMatchError = nil
                }
            }
        }
    }
    
    // MARK: - Password Validation
    
    private func validatePassword(_ password: String) -> (isValid: Bool, errorMessage: String?, strength: PasswordStrength) {
        // Check minimum length
        guard password.count >= 8 else {
            return (false, "Password must be at least 8 characters long", .weak)
        }
        
        // Check for at least one uppercase letter
        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        guard hasUppercase else {
            return (false, "Password must contain at least one uppercase letter", .weak)
        }
        
        // Check for at least one lowercase letter
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        guard hasLowercase else {
            return (false, "Password must contain at least one lowercase letter", .weak)
        }
        
        // Check for at least one number
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        guard hasNumber else {
            return (false, "Password must contain at least one number", .weak)
        }
        
        // Check for common passwords
        let commonPasswords = ["password", "12345678", "password123", "qwerty123", "abc12345", 
                               "Password1", "Password123", "Welcome1", "Welcome123"]
        let lowercased = password.lowercased()
        if commonPasswords.contains(where: { lowercased.contains($0.lowercased()) }) {
            return (false, "This password is too common. Please choose a more unique password.", .weak)
        }
        
        // Calculate strength
        let hasSpecialChar = password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil
        let length = password.count
        
        let strength: PasswordStrength
        if length >= 12 && hasUppercase && hasLowercase && hasNumber && hasSpecialChar {
            strength = .strong
        } else if length >= 10 && hasUppercase && hasLowercase && hasNumber {
            strength = .strong
        } else if length >= 8 && hasUppercase && hasLowercase && hasNumber {
            strength = .medium
        } else {
            strength = .weak
        }
        
        return (true, nil, strength)
    }
}

// MARK: - Password Visibility Toggle

/// Shared by SignInView and DeleteAccountView (re-auth) — keep behavior identical.
struct PasswordVisibilityToggle: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash" : "eye")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isVisible ? "Hide password" : "Show password").localized)
    }
}

// MARK: - Sign In Password Field (SwiftUI)

/// Sign-in only — SwiftUI SecureField/TextField. Eye toggle overlays trailing (Z-order).
private struct SignInPasswordField: View {
    @Binding var text: String
    var isVisible: Bool
    var placeholder: String
    
    var body: some View {
        Group {
            if isVisible {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
        .textContentType(.password)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .rounded))
        .autocapitalization(.none)
    }
}

// MARK: - New Password AutoFill Field (UIKit)

/// Create-account password fields. UITextField so Strong Password AutoFill can write the value;
/// after bulk insert, secure entry is toggled so bullet glyphs match string length.
private struct NewPasswordAutoFillField: UIViewRepresentable {
    @Binding var text: String
    var isVisible: Bool
    var placeholder: String
    /// Extra trailing inset so typed text clears the overlaid eye button.
    var trailingContentInset: CGFloat = 0
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.font = Self.roundedBodyFont()
        textField.textColor = .label
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.textContentType = .newPassword
        textField.isSecureTextEntry = !isVisible
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        Self.applyTrailingInset(trailingContentInset, to: textField)
        context.coordinator.observeTextChanges(on: textField)
        context.coordinator.applyText(text, to: textField, isVisible: isVisible)
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.applyText(text, to: uiView, isVisible: isVisible)
        Self.applyTrailingInset(trailingContentInset, to: uiView)
        
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
        
        uiView.textColor = .label
    }
    
    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.stopObserving()
    }
    
    private static func applyTrailingInset(_ inset: CGFloat, to textField: UITextField) {
        guard inset > 0 else {
            textField.rightView = nil
            textField.rightViewMode = .never
            return
        }
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: inset, height: 1))
        textField.rightView = spacer
        textField.rightViewMode = .always
    }
    
    private static func roundedBodyFont() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
    
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        private var isRefreshingSecureDisplay = false
        private var textChangeObserver: NSObjectProtocol?
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        func observeTextChanges(on textField: UITextField) {
            stopObserving()
            textChangeObserver = NotificationCenter.default.addObserver(
                forName: UITextField.textDidChangeNotification,
                object: textField,
                queue: .main
            ) { [weak self, weak textField] _ in
                guard let self, let textField else { return }
                self.handleTextChange(on: textField)
            }
        }
        
        func stopObserving() {
            if let textChangeObserver {
                NotificationCenter.default.removeObserver(textChangeObserver)
                self.textChangeObserver = nil
            }
        }
        
        @objc func editingChanged(_ textField: UITextField) {
            handleTextChange(on: textField)
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            handleTextChange(on: textField)
        }
        
        private func handleTextChange(on textField: UITextField) {
            guard !isRefreshingSecureDisplay else { return }
            let newValue = textField.text ?? ""
            if text.wrappedValue != newValue {
                text.wrappedValue = newValue
            }
            // Defer past AutoFill's own layout pass; secure fields often show one bullet until toggled.
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField else { return }
                self.refreshSecureBulletDisplay(textField)
            }
        }
        
        /// Assign text without the secure-field single-bullet glitch after programmatic / AutoFill writes.
        func applyText(_ value: String, to textField: UITextField, isVisible: Bool) {
            let shouldSecure = !isVisible
            let textNeedsUpdate = textField.text != value
            let secureNeedsUpdate = textField.isSecureTextEntry != shouldSecure
            guard textNeedsUpdate || secureNeedsUpdate else {
                textField.textColor = .label
                return
            }
            
            isRefreshingSecureDisplay = true
            defer { isRefreshingSecureDisplay = false }
            
            // Toggle secure entry around text assignment so glyph count matches string length.
            textField.isSecureTextEntry = false
            textField.text = value
            textField.isSecureTextEntry = shouldSecure
            if shouldSecure {
                // Re-assert text after enabling secure entry (UIKit sometimes truncates glyphs otherwise).
                textField.text = value
            }
            textField.textColor = .label
        }
        
        /// AutoFill can leave the model correct but only one secure glyph drawn — force a redraw.
        private func refreshSecureBulletDisplay(_ textField: UITextField) {
            guard !isRefreshingSecureDisplay else { return }
            guard textField.isSecureTextEntry else { return }
            let value = textField.text ?? ""
            guard value.count > 1 else { return }
            
            isRefreshingSecureDisplay = true
            defer { isRefreshingSecureDisplay = false }
            
            textField.isSecureTextEntry = false
            textField.text = value
            textField.isSecureTextEntry = true
            textField.text = value
            textField.textColor = .label
        }
    }
}

// MARK: - Password Requirement Component

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isMet ? .green : Color.Theme.softBrown)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(isMet ? Color.Theme.primaryBlue : Color.Theme.softBrown)
        }
    }
}

// MARK: - Child create-account guidance (COPPA F-18, FR-60(e))

/// What an under-13 epoch sees instead of the create-account form.
///
/// Non-punitive by construction: nothing here reads as a refusal or a lock-out. The child is
/// already playing — locally, fully, with their history on the device — and the only thing an
/// account would have added is the family features a parent has to consent to anyway. So the
/// screen states the good news first and offers the share-code route as the way forward.
///
/// Deliberately logs NO analytics: an event here fires only for child sessions on the child's
/// own device (FR-21 / SRS §12), which is the case the taxonomy must never carry.
struct ChildAccountCreationGuidanceView: View {
    /// Passed explicitly rather than read from the environment: `SignInView` takes its auth
    /// service as an `@ObservedObject` parameter, and `JoinFamilySheet` requires the
    /// `@EnvironmentObject`. Relying on sheet environment inheritance here is exactly the
    /// fragility that once made the child's join route silently present nothing (see
    /// `ChildFamilyPromptBanner`).
    @ObservedObject var authService: FirebaseAuthService
    let onKeepPlaying: () -> Void
    let onSwitchToSignIn: () -> Void

    @State private var showJoinFamilySheet = false

    private var title: String { "child_gate.signup.title".localized }
    private var bodyText: String { "child_gate.signup.body".localized }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibleDecorative()
                    .padding(.top, 32)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                        .accessibleHeader(title)
                        .supportsDynamicType()

                    Text(bodyText)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .supportsDynamicType()
                }
                .accessibilityElement(children: .contain)

                VStack(spacing: 12) {
                    Button {
                        showJoinFamilySheet = true
                    } label: {
                        Text("Join a Family".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.Theme.primaryBlue))
                            .foregroundStyle(.white)
                    }
                    .accessibleButton(
                        label: "Join a Family".localized,
                        hint: "child_gate.screen.join_button_hint".localized
                    )

                    Button {
                        onKeepPlaying()
                    } label: {
                        Text("child_gate.signup.keep_playing".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().stroke(Color.Theme.primaryBlue, lineWidth: 1.5)
                            )
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .accessibleButton(
                        label: "child_gate.signup.keep_playing".localized,
                        hint: "child_gate.signup.keep_playing_hint".localized
                    )
                }
                .padding(.horizontal, 24)

                // Sign-in stays reachable: FR-27 forbids ASKING the age question at sign-in,
                // not signing in. A child with an existing account still needs the door.
                Button {
                    onSwitchToSignIn()
                } label: {
                    Text("Already have an account? Sign in")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet()
                .environmentObject(authService)
        }
    }
}

// MARK: - OAuth Button Component

struct OAuthButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
            )
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    SignInView(authService: FirebaseAuthService())
        .modelContainer(for: AppUser.self, inMemory: true)
}

#Preview("Create account") {
    SignInView(authService: FirebaseAuthService(), initialMode: .createAccount)
        .modelContainer(for: AppUser.self, inMemory: true)
}

#Preview("Child create-account guidance") {
    AppBackgroundView {
        ChildAccountCreationGuidanceView(
            authService: FirebaseAuthService(),
            onKeepPlaying: {},
            onSwitchToSignIn: {}
        )
    }
    .environmentObject(FirebaseAuthService())
}

#Preview("Child create-account guidance — dark, large text") {
    AppBackgroundView {
        ChildAccountCreationGuidanceView(
            authService: FirebaseAuthService(),
            onKeepPlaying: {},
            onSwitchToSignIn: {}
        )
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
    .environmentObject(FirebaseAuthService())
}
