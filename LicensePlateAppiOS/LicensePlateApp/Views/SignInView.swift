import SwiftUI
import SwiftData

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
    
    @State private var isSignInMode = true // true = sign in, false = create account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var userName = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phoneNumber = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
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
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .textContentType(.username)
                                }
                                
                                // First Name field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("First Name")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    TextField("Enter your first name", text: $firstName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .autocapitalization(.words)
                                        .textContentType(.givenName)
                                }
                                
                                // Last Name field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Last Name")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    TextField("Enter your last name", text: $lastName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .autocapitalization(.words)
                                        .textContentType(.familyName)
                                }
                            }
                            
                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                TextField("Enter your email", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .rounded))
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .textContentType(isSignInMode ? .emailAddress : .emailAddress)
                            }
                            
                            if !isSignInMode {
                                // Phone Number field (only for create account)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Phone Number (Optional)")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    TextField("Enter your phone number", text: $phoneNumber)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .keyboardType(.phonePad)
                                        .autocapitalization(.none)
                                        .textContentType(.telephoneNumber)
                                }
                            }
                            
                            // Password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                SecureField("Enter your password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .rounded))
                                    .textContentType(isSignInMode ? .password : .newPassword)
                                    .autocorrectionDisabled()
                                
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
                                    
                                    SecureField("Confirm your password", text: $confirmPassword)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .textContentType(.newPassword)
                                        .autocorrectionDisabled()
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
                                        // Autofill from current user
                                        if let currentUser = authService.currentUser {
                                            userName = currentUser.userName
                                            firstName = currentUser.firstName ?? ""
                                            lastName = currentUser.lastName ?? ""
                                            phoneNumber = currentUser.phoneNumber ?? ""
                                        }
                                    } else {
                                        // Switching to sign in - clear all fields
                                        password = ""
                                        confirmPassword = ""
                                        userName = ""
                                        firstName = ""
                                        lastName = ""
                                        phoneNumber = ""
                                    }
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
            .onChange(of: authService.isAuthenticated) { oldValue, newValue in
                // Auto-dismiss when authentication succeeds
                if newValue && oldValue == false {
                    dismiss()
                    authService.showSignInSheet = false
                }
            }
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
        firstName = ""
        lastName = ""
        phoneNumber = ""
        errorMessage = ""
    }
    
    private func signIn() {
        guard isFormValid else { return }
        
        isLoading = true
        Task {
            do {
                try await authService.signIn(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    authService.showSignInSheet = false
                    dismiss()
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
                    userName: userName,
                    firstName: firstName.isEmpty ? nil : firstName,
                    lastName: lastName.isEmpty ? nil : lastName,
                    phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber
                )
                await MainActor.run {
                    isLoading = false
                    authService.showSignInSheet = false
                    dismiss()
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
                    authService.showSignInSheet = false
                    dismiss()
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
                    authService.showSignInSheet = false
                    dismiss()
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
