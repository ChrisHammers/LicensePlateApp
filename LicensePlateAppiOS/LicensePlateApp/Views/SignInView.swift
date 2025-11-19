import SwiftUI
import SwiftData

struct SignInView: View {
    @ObservedObject var authService: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var isSignInMode = true // true = sign in, false = create account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var userName = ""
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
                                    isSignInMode.toggle()
                                    clearForm()
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
            return !userName.isEmpty && !email.isEmpty && !password.isEmpty && password == confirmPassword && password.count >= 6
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        userName = ""
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
        
      //TODO: this should be more secure than 6 char long.
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            showError = true
            return
        }
        
        isLoading = true
        Task {
            do {
                try await authService.createAccount(email: email, password: password, userName: userName)
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
