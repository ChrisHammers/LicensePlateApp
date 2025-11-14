//
//  FirebaseAuthService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Combine
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
    
    // Firebase Auth instance (uncomment when Firebase is configured)
    // private let auth = Auth.auth()
    // private let db = Firestore.firestore()
    
    init() {
        // Initialize with local user for now
        // When Firebase is configured, observe auth state changes
        // auth.addStateDidChangeListener { [weak self] auth, user in
        //     Task { @MainActor in
        //         await self?.handleAuthStateChange(user)
        //     }
        // }
    }
    
    // MARK: - Authentication Methods (to be implemented with Firebase)
    
    /// Sign in anonymously (for local-only mode)
    func signInAnonymously() async throws {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implement Firebase anonymous sign-in
        // let result = try await auth.signInAnonymously()
        // await loadUserData(userId: result.user.uid)
        
        // For now, create a local user
        // Check if user already exists in SwiftData (will be handled by app initialization)
        let localUser = AppUser(
            id: UUID().uuidString,
            userName: "User",
            createdAt: .now
        )
        currentUser = localUser
        isAuthenticated = true
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
    
    /// Update user name
    func updateUserName(_ newName: String) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        user.updateUserName(newName)
        // currentUser is already a reference, so the update is reflected automatically
        
        // TODO: Save to Firestore when Firebase is configured
        // try await saveUserData(user)
    }
    
    // MARK: - Platform Linking (to be implemented)
    
    /// Link a platform account
    func linkPlatform(_ platform: LinkedPlatform.PlatformType, userId: String) async throws {
        // TODO: Implement platform linking with Firebase
        // This will use Firebase's linkWithCredential methods
        throw AuthError.notImplemented
    }
    
    /// Unlink a platform account
    func unlinkPlatform(_ platform: LinkedPlatform.PlatformType) async throws {
        // TODO: Implement platform unlinking
        throw AuthError.notImplemented
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
        }
    }
}

