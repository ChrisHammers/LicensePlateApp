//
//  FirebaseAuthService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Combine
import SwiftData
// import FirebaseAuth
// import FirebaseFirestore

/// Firebase Authentication Service
/// Note: Firebase SDK imports are commented out until GoogleService-Info.plist is added
/// Uncomment the imports and implement the methods when Firebase is configured
@MainActor
class FirebaseAuthService: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showUsernameConflictDialog = false
    @Published var conflictDialogMessage = ""
    @Published var conflictDialogNewUsername = ""
    
    // Callback for username conflict resolution
    var usernameConflictResolver: ((String?) -> Void)?
    
    // Firebase Auth instance (uncomment when Firebase is configured)
    // private let auth = Auth.auth()
    // private let db = Firestore.firestore()
    
    private var modelContext: ModelContext?
    
    init() {
        // Initialize with local user for now
        // When Firebase is configured, observe auth state changes
        // auth.addStateDidChangeListener { [weak self] auth, user in
        //     Task { @MainActor in
        //         await self?.handleAuthStateChange(user)
        //     }
        // }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Default Username Generation
    
    /// Create or get default user with device-based username
    func createDefaultUser(modelContext: ModelContext) async throws -> AppUser {
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        
        // Check if user already exists for this device
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.deviceIdentifier == deviceId }
        )
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            currentUser = existingUser
            isAuthenticated = true
            return existingUser
        }
        
        // Generate default username
        var defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        
        // Check uniqueness and regenerate if needed
        while try await isUsernameTaken(defaultUsername) {
            defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        }
        
        // Create new user
        let newUser = AppUser(
            id: UUID().uuidString,
            userName: defaultUsername,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: false
        )
        
        modelContext.insert(newUser)
        try modelContext.save()
        
        currentUser = newUser
        isAuthenticated = true
        
        // Save to Firestore when Firebase is configured
        // try await saveUserData(newUser)
        
        return newUser
    }
    
    // MARK: - Username Uniqueness Checking
    
    /// Check if username is already taken
    func isUsernameTaken(_ username: String) async throws -> Bool {
        // TODO: When Firebase is configured, check Firestore
        // let usersRef = db.collection("users")
        // let query = usersRef.whereField("userName", isEqualTo: username).limit(to: 1)
        // let snapshot = try await query.getDocuments()
        // return !snapshot.documents.isEmpty
        
        // For now, check local SwiftData
        guard let modelContext = modelContext else { return false }
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.userName == username }
        )
        let users = try? modelContext.fetch(descriptor)
        return !(users?.isEmpty ?? true)
    }
    
    // MARK: - Authentication Methods
    
    /// Sign in anonymously (for local-only mode)
    func signInAnonymously() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let modelContext = modelContext else {
            throw AuthError.notImplemented
        }
        
        // TODO: Implement Firebase anonymous sign-in
        // let result = try await auth.signInAnonymously()
        // await loadUserData(userId: result.user.uid)
        
        // For now, create default user
        _ = try await createDefaultUser(modelContext: modelContext)
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement Firebase email/password sign-in
        // let result = try await auth.signIn(withEmail: email, password: password)
        // await loadUserData(userId: result.user.uid)
        
        throw AuthError.notImplemented
    }
    
    /// Create account with email and password
    func createAccount(email: String, password: String, userName: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Check username uniqueness
        guard try await !isUsernameTaken(userName) else {
            throw AuthError.usernameTaken
        }
        
        // TODO: Implement Firebase account creation
        // let result = try await auth.createUser(withEmail: email, password: password)
        // let user = AppUser(id: result.user.uid, userName: userName, email: email)
        // try await saveUserData(user)
        // currentUser = user
        // isAuthenticated = true
        
        throw AuthError.notImplemented
    }
    
    /// Sign out
    func signOut() async throws {
        // TODO: Implement Firebase sign out
        // try auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }
    
    // MARK: - User Data Methods
    
    /// Load user data from Firestore
    func loadUserData(userId: String) async {
        // TODO: Implement Firestore user data loading
        // let docRef = db.collection("users").document(userId)
        // let document = try? await docRef.getDocument()
        // if let data = document?.data() {
        //     currentUser = AppUser(from: data)
        // }
    }
    
    /// Save user data to Firestore
    func saveUserData(_ user: AppUser) async throws {
        // TODO: Implement Firestore user data saving
        // let docRef = db.collection("users").document(user.id)
        // try await docRef.setData(user.toDictionary())
    }
    
    /// Update user name with uniqueness check
    func updateUserName(_ newName: String) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw AuthError.invalidUsername
        }
        
        // Check if username changed
        guard trimmedName != user.userName else {
            return // No change needed
        }
        
        // Check uniqueness
        guard try await !isUsernameTaken(trimmedName) else {
            throw AuthError.usernameTaken
        }
        
        user.updateUserName(trimmedName, isManual: true)
        
        // Save to SwiftData
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        // TODO: Save to Firestore when Firebase is configured
        // try await saveUserData(user)
    }
    
    // MARK: - Platform Linking
    
    /// Link a platform account (Google, Apple, etc.)
    func linkPlatform(_ platform: LinkedPlatform.PlatformType, credential: Any) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement Firebase platform linking
        // let authCredential = credential as! AuthCredential
        // let result = try await auth.currentUser?.link(with: authCredential)
        
        // For now, simulate the linking process
        // Extract info from credential (this would come from Firebase)
        let platformInfo = LinkedPlatform(
            platform: platform,
            platformUserId: UUID().uuidString, // Would be actual platform user ID
            linkedAt: .now,
            email: nil, // Would extract from credential
            phoneNumber: nil, // Would extract from credential
            displayName: nil // Would extract from credential
        )
        
        // Check username conflict if username hasn't been manually changed
        if !user.isUsernameManuallyChanged {
            // Check if username is taken
            if try await isUsernameTaken(user.userName) {
                // Show conflict dialog
                await showUsernameConflictDialogForLinking(platform: platform)
                return
            }
        }
        
        // Add platform to linked platforms
        user.linkedPlatforms.append(platformInfo)
        
        // Update email/phone if available and not set
        if let email = platformInfo.email, user.email == nil {
            user.email = email
        }
        if let phone = platformInfo.phoneNumber, user.phoneNumber == nil {
            user.phoneNumber = phone
        }
        
        // Save to SwiftData
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        // TODO: Save to Firestore when Firebase is configured
        // try await saveUserData(user)
    }
    
    /// Show username conflict dialog during linking
    private func showUsernameConflictDialogForLinking(platform: LinkedPlatform.PlatformType) async {
        conflictDialogMessage = "Your username '\(currentUser?.userName ?? "")' is already taken. Please choose a new username to link your \(platform.rawValue) account."
        conflictDialogNewUsername = ""
        showUsernameConflictDialog = true
        
        // Wait for user response via callback
        await withCheckedContinuation { continuation in
            usernameConflictResolver = { newUsername in
                continuation.resume()
                self.usernameConflictResolver = nil
                
                if let username = newUsername {
                    Task { @MainActor in
                        do {
                            try await self.updateUserName(username)
                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    // User cancelled - reverse the linking
                    Task { @MainActor in
                        // TODO: Unlink the platform if already linked
                        self.errorMessage = "Account linking cancelled."
                    }
                }
            }
        }
    }
    
    /// Resolve username conflict (called from dialog)
    func resolveUsernameConflict(newUsername: String?) {
        usernameConflictResolver?(newUsername)
    }
    
    /// Unlink a platform account
    func unlinkPlatform(_ platform: LinkedPlatform.PlatformType) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        // TODO: Implement Firebase platform unlinking
        // try await auth.currentUser?.unlink(fromProvider: platform.rawValue)
        
        // Remove from linked platforms
        user.linkedPlatforms.removeAll { $0.platform == platform }
        
        // Save to SwiftData
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        // TODO: Save to Firestore when Firebase is configured
        // try await saveUserData(user)
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthStateChange(_ user: Any?) async {
        // TODO: Handle Firebase auth state changes
        // if let firebaseUser = user {
        //     await loadUserData(userId: firebaseUser.uid)
        //     isAuthenticated = true
        // } else {
        //     currentUser = nil
        //     isAuthenticated = false
        // }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notImplemented
    case noUser
    case invalidCredentials
    case networkError
    case usernameTaken
    case invalidUsername
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Firebase authentication is not yet configured. Please add GoogleService-Info.plist to enable this feature."
        case .noUser:
            return "No user is currently signed in."
        case .invalidCredentials:
            return "Invalid email or password."
        case .networkError:
            return "Network error. Please check your connection."
        case .usernameTaken:
            return "This username is already taken. Please choose another."
        case .invalidUsername:
            return "Username cannot be empty."
        }
    }
}
