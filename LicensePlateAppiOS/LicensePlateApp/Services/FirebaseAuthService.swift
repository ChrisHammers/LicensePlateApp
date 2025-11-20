//
//  FirebaseAuthService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Combine
import SwiftData
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import AuthenticationServices
import GoogleSignIn
import Network
import CryptoKit

/// Network monitoring for offline detection
@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

/// Firebase Authentication Service with offline-first architecture
/// The app works completely offline - Firebase is used for sync when online
@MainActor
class FirebaseAuthService: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showUsernameConflictDialog = false
    @Published var conflictDialogMessage = ""
    @Published var conflictDialogNewUsername = ""
    @Published var showSignInSheet = false
    
    // Callback for username conflict resolution
    var usernameConflictResolver: ((String?) -> Void)?
    
    // Firebase instances
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    private var modelContext: ModelContext?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let networkMonitor = NetworkMonitor()
    
    init() {
        // Observe auth state changes (only affects online sync)
        authStateListener = auth.addStateDidChangeListener { [weak self] auth, user in
            Task { @MainActor in
                await self?.handleAuthStateChange(user)
            }
        }
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Network Status
    
    /// Check if device is online
    var isOnline: Bool {
        networkMonitor.isConnected
    }
    
    // MARK: - Default Username Generation
    
    /// Create or get default user with device-based username (works offline)
    func createDefaultUser(modelContext: ModelContext) async throws -> AppUser {
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        
        // Check if user already exists for this device (offline check)
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.deviceIdentifier == deviceId }
        )
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            currentUser = existingUser
            isAuthenticated = true
            
            // Try to sync if online (non-blocking)
            if isOnline && existingUser.needsSync {
                Task {
                    try? await syncUserToFirebase(existingUser)
                }
            }
            
            return existingUser
        }
        
        // Generate default username (offline)
        var defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        
        // Check uniqueness locally first (always works offline)
        var attempts = 0
        while try await isUsernameTakenLocally(defaultUsername) && attempts < 10 {
            defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
            attempts += 1
        }
        
        // Create new local user (works offline)
        let localID = UUID().uuidString
        let newUser = AppUser(
            id: localID,
            userName: defaultUsername,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: false,
            needsSync: true // Mark for sync when online
        )
        
        modelContext.insert(newUser)
        try modelContext.save()
        
        currentUser = newUser
        isAuthenticated = true
        
        // Try to sync to Firebase if online (non-blocking, doesn't block app)
        if isOnline {
            Task {
                try? await syncLocalUserToFirebase(newUser)
            }
        }
        
        return newUser
    }
    
    // MARK: - Username Uniqueness Checking
    
    /// Check if username is taken locally (always works offline)
    func isUsernameTakenLocally(_ username: String) async throws -> Bool {
        guard let modelContext = modelContext else { return false }
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.userName == username }
        )
        let users = try? modelContext.fetch(descriptor)
        return !(users?.isEmpty ?? true)
    }
    
    /// Check if username is taken (checks local first, then Firebase if online)
    func isUsernameTaken(_ username: String) async throws -> Bool {
        // Always check local first (works offline)
        if try await isUsernameTakenLocally(username) {
            return true
        }
        
        // Check Firebase if online
        guard isOnline else {
            return false // If offline, only local check matters
        }
        
        do {
            let usersRef = db.collection("users")
            let query = usersRef.whereField("userName", isEqualTo: username).limit(to: 1)
            let snapshot = try await query.getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            // If Firebase check fails, fall back to local-only
            print("⚠️ Firebase username check failed, using local-only: \(error)")
            return false
        }
    }
    
    // MARK: - Authentication Methods (Offline-First)
    
    /// Sign in anonymously (creates local user, syncs to Firebase if online)
    func signInAnonymously() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let modelContext = modelContext else {
            throw AuthError.notImplemented
        }
        
        // Always create local user first (works offline)
        _ = try await createDefaultUser(modelContext: modelContext)
        
        // Try Firebase anonymous auth if online (non-blocking)
        if isOnline {
            do {
                let result = try await auth.signInAnonymously()
                await linkLocalUserToFirebase(localUser: currentUser!, firebaseUID: result.user.uid)
            } catch {
                // Firebase failed, but local user exists - app still works
                print("⚠️ Firebase anonymous sign-in failed, continuing with local user: \(error)")
            }
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            throw AuthError.networkError
        }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            let firebaseUID = result.user.uid
            
            // Check if we have a local user to migrate
            if let localUser = currentUser, localUser.firebaseUID == nil {
                // Migrate local user to Firebase
                try await migrateLocalUserToFirebase(localUser: localUser, firebaseUID: firebaseUID)
            } else {
                // Load user from Firestore or create new
                await loadOrCreateUserFromFirebase(firebaseUID: firebaseUID, email: email)
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17008, 17009, 17010, 17011:
                    throw AuthError.invalidCredentials
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Create account with email and password
    func createAccount(email: String, password: String, userName: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        // Check username uniqueness (works offline for local, online for Firebase)
        guard try await !isUsernameTaken(userName) else {
            throw AuthError.usernameTaken
        }
        
        guard isOnline else {
            // Create local account, mark for sync
            guard let modelContext = modelContext else {
                throw AuthError.notImplemented
            }
            
            let localID = UUID().uuidString
            let newUser = AppUser(
                id: localID,
                userName: userName,
                email: email,
                deviceIdentifier: DeviceIdentifier.getDeviceIdentifier(),
                isUsernameManuallyChanged: true,
                needsSync: true
            )
            
            modelContext.insert(newUser)
            try modelContext.save()
            
            currentUser = newUser
            isAuthenticated = true
            
            // Will sync to Firebase when online
            return
        }
        
        do {
            // Create Firebase account
            let result = try await auth.createUser(withEmail: email, password: password)
            let firebaseUID = result.user.uid
            
            // Check if we have a local user to migrate
            if let localUser = currentUser, localUser.firebaseUID == nil {
                // Migrate local user to Firebase account
                try await migrateLocalUserToFirebase(localUser: localUser, firebaseUID: firebaseUID, email: email, userName: userName)
            } else {
                // Create new user with Firebase UID
                let newUser = AppUser(
                    id: firebaseUID,
                    userName: userName,
                    email: email,
                    deviceIdentifier: DeviceIdentifier.getDeviceIdentifier(),
                    isUsernameManuallyChanged: true,
                    firebaseUID: firebaseUID
                )
                
                modelContext?.insert(newUser)
                try modelContext?.save()
                
                currentUser = newUser
                isAuthenticated = true
                
                // Save to Firestore (ensure it's saved)
                do {
                    try await saveUserDataToFirestore(newUser)
                    print("✅ User \(newUser.userName) saved to Firestore successfully")
                } catch {
                    print("⚠️ Failed to save user to Firestore: \(error)")
                    // Continue anyway - user is created locally and will sync later
                }
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17007:
                    throw AuthError.emailAlreadyInUse
                case 17008:
                    throw AuthError.invalidCredentials
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Sign out (keeps local user, just disconnects from Firebase)
    func signOut() async throws {
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        // Sign out from Firebase if online
        if isOnline {
            do {
                try auth.signOut()
            } catch {
                print("⚠️ Firebase sign out failed: \(error)")
                // Continue with local sign out even if Firebase fails
            }
        }
        
        // Update local user to disconnect from Firebase
        if let user = currentUser {
            // Store the local ID before clearing Firebase UID
            if user.firebaseUID != nil {
                user.localIDBeforeFirebase = user.id
            }
            
            // Clear Firebase authentication but keep local user
            user.firebaseUID = nil
            user.linkedPlatforms.removeAll()
            user.needsSync = false // No longer needs sync since we're local-only
            user.lastSyncedToFirebase = nil
            
            // If the user's ID was a Firebase UID, we need to generate a new local ID
            // But we should keep the same user object, so we'll keep the ID as is
            // The user will get a new Firebase UID if they sign in again
            
            try modelContext.save()
        }
        
        // Update authentication state
        isAuthenticated = false
        // Keep currentUser so the app still works offline
    }
    
    // MARK: - User Migration (Local to Firebase)
    
    /// Migrate local user to Firebase account
    private func migrateLocalUserToFirebase(
        localUser: AppUser,
        firebaseUID: String,
        email: String? = nil,
        userName: String? = nil
    ) async throws {
        guard let modelContext = modelContext else {
            throw AuthError.notImplemented
        }
        
        // Store original local ID
        let originalLocalID = localUser.id
        localUser.localIDBeforeFirebase = originalLocalID
        
        // Update user with Firebase info
        localUser.firebaseUID = firebaseUID
        localUser.id = firebaseUID // Change primary ID to Firebase UID
        if let email = email {
            localUser.email = email
        }
        if let userName = userName {
            localUser.userName = userName
            localUser.isUsernameManuallyChanged = true
        }
        
        // Update all trips that reference the old user ID
        let tripDescriptor = FetchDescriptor<Trip>()
        if let trips = try? modelContext.fetch(tripDescriptor) {
            for trip in trips {
                // Update foundRegions that reference the old user ID
                for i in 0..<trip.foundRegions.count {
                    if trip.foundRegions[i].foundBy == originalLocalID {
                        trip.foundRegions[i].foundBy = firebaseUID
                    }
                }
            }
        }
        
        try modelContext.save()
        
        // Save to Firestore
        try await saveUserDataToFirestore(localUser)
        
        currentUser = localUser
    }
    
    /// Link local user to Firebase (for anonymous auth)
    private func linkLocalUserToFirebase(localUser: AppUser, firebaseUID: String) async {
        guard let modelContext = modelContext else { return }
        
        let originalLocalID = localUser.id
        localUser.localIDBeforeFirebase = originalLocalID
        localUser.firebaseUID = firebaseUID
        localUser.id = firebaseUID
        
        // Update trips
        let tripDescriptor = FetchDescriptor<Trip>()
        if let trips = try? modelContext.fetch(tripDescriptor) {
            for trip in trips {
                for i in 0..<trip.foundRegions.count {
                    if trip.foundRegions[i].foundBy == originalLocalID {
                        trip.foundRegions[i].foundBy = firebaseUID
                    }
                }
            }
        }
        
        try? modelContext.save()
        
        // Sync to Firestore
        try? await saveUserDataToFirestore(localUser)
    }
    
    /// Load or create user from Firebase
    private func loadOrCreateUserFromFirebase(firebaseUID: String, email: String?) async {
        guard let modelContext = modelContext else { return }
        
        // Check if user exists locally
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.id == firebaseUID }
        )
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            currentUser = existingUser
          print("Loaded existing user \(currentUser?.firebaseUID ?? "unknown")--\(currentUser?.userName ?? "unknown")")
            isAuthenticated = true
            return
        }
        
        // Try to load from Firestore
        if let firestoreUser = try? await loadUserDataFromFirestore(userId: firebaseUID) {
            modelContext.insert(firestoreUser)
            try? modelContext.save()
            currentUser = firestoreUser
            print("Loaded user \(currentUser?.firebaseUID ?? "unknown")--\(currentUser?.userName ?? "unknown")")
            isAuthenticated = true
        } else {
            // Create new user from Firebase auth
            let newUser = AppUser(
                id: firebaseUID,
                userName: email?.components(separatedBy: "@").first ?? "User",
                email: email,
                firebaseUID: firebaseUID
            )
            modelContext.insert(newUser)
            try? modelContext.save()
            currentUser = newUser
            isAuthenticated = true
            
            // Save to Firestore (ensure it's saved)
            do {
                try await saveUserDataToFirestore(newUser)
            } catch {
                print("⚠️ Failed to save user to Firestore: \(error)")
                // Continue anyway - user is created locally
            }
        }
    }
    
    // MARK: - Firestore Serialization
    
    private func loadUserDataFromFirestore(userId: String) async throws -> AppUser? {
        let docRef = db.collection("users").document(userId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return appUserFromFirestoreData(data, id: userId)
    }
    
    /// Save user data to Firestore (non-blocking, works offline)
    func saveUserDataToFirestore(_ user: AppUser) async throws {
        guard isOnline else {
            // Mark for sync when online
            user.needsSync = true
            try? modelContext?.save()
            return
        }
        
        guard let firebaseUID = user.firebaseUID else {
            // Local-only user, can't save to Firestore yet
            user.needsSync = true
            return
        }
        
        let docRef = db.collection("users").document(firebaseUID)
        let data = firestoreDataFromAppUser(user)
        try await docRef.setData(data, merge: true)
        
        user.lastSyncedToFirebase = .now
        user.needsSync = false
        try? modelContext?.save()
    }
    
    /// Sync local user to Firebase (for default users)
    private func syncLocalUserToFirebase(_ user: AppUser) async throws {
        guard isOnline, user.firebaseUID == nil else { return }
        
        // Try anonymous Firebase auth
        do {
            let result = try await auth.signInAnonymously()
            await linkLocalUserToFirebase(localUser: user, firebaseUID: result.user.uid)
        } catch {
            // Failed, but that's OK - user still works offline
            print("⚠️ Could not sync local user to Firebase: \(error)")
        }
    }
    
    /// Sync user to Firebase if needed (called periodically)
    func syncUserToFirebase(_ user: AppUser) async throws {
        guard isOnline, user.needsSync else { return }
        
        if user.firebaseUID == nil {
            // Try to create anonymous Firebase account
            try await syncLocalUserToFirebase(user)
        } else {
            // Sync existing Firebase user
            try await saveUserDataToFirestore(user)
        }
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
        
        guard trimmedName != user.userName else {
            return
        }
        
        // Check uniqueness (works offline for local, online for Firebase)
        guard try await !isUsernameTaken(trimmedName) else {
            throw AuthError.usernameTaken
        }
        
        user.updateUserName(trimmedName, isManual: true)
        user.needsSync = true
        
        // Save locally (always works)
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        // Try to sync to Firebase if online (non-blocking)
        if isOnline {
            Task {
                try? await saveUserDataToFirestore(user)
            }
        }
    }
    
    // MARK: - Apple Nonce Helpers

    private static func sha256(_ input: String) -> String {
        guard let inputData = input.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }
    
    // MARK: - Platform Linking
    
    /// Sign in with Google (creates account if needed)
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthError.notImplemented
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            let googleUser = result.user
            guard let idToken = googleUser.idToken?.tokenString else {
                throw AuthError.networkError
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: googleUser.accessToken.tokenString)
            
            // Sign in with Firebase
            let authResult = try await auth.signIn(with: credential)
            let firebaseUID = authResult.user.uid
            
            // Check if user exists locally or in Firestore
            if let existingUser = currentUser, existingUser.firebaseUID == nil {
                // Migrate local user to Firebase
                try await migrateLocalUserToFirebase(localUser: existingUser, firebaseUID: firebaseUID, email: googleUser.profile?.email)
            } else {
                // Load or create user from Firebase
                await loadOrCreateUserFromFirebase(firebaseUID: firebaseUID, email: googleUser.profile?.email)
                
                // Add Google as linked platform
                if let user = currentUser {
                    let platformInfo = LinkedPlatform(
                        platform: .google,
                        platformUserId: firebaseUID,
                        linkedAt: .now,
                        email: googleUser.profile?.email,
                        phoneNumber: nil,
                        displayName: googleUser.profile?.name
                    )
                    
                    if !user.linkedPlatforms.contains(where: { $0.platform == .google }) {
                        user.linkedPlatforms.append(platformInfo)
                    }
                    
                    try modelContext.save()
                    try await saveUserDataToFirestore(user)
                }
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020: // Account exists with different credential
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Link Google account (for existing users)
    func linkGoogleAccount(presentingViewController: UIViewController) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.networkError
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthError.notImplemented
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            let googleUser = result.user
            guard let idToken = googleUser.idToken?.tokenString else {
                throw AuthError.networkError
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: googleUser.accessToken.tokenString)
            
            try await linkPlatformCredential(credential, platform: .google, email: googleUser.profile?.email, displayName: googleUser.profile?.name)
        } catch {
            throw AuthError.networkError
        }
    }
    
    /// Sign in with Apple (creates account if needed)
    func signInWithApple() async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
                authorizationController.delegate = AppleSignInDelegate(continuation: continuation)
                authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
                authorizationController.performRequests()
            }
            
            guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.networkError
            }
            
            // Create OAuth credential for Apple Sign-In using nonce
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)

            // Sign in with Firebase
            let authResult = try await auth.signIn(with: credential)
            let firebaseUID = authResult.user.uid
            
            let email = appleIDCredential.email
            let displayName = appleIDCredential.fullName.map { name in
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
            
            // Check if user exists locally or in Firestore
            if let existingUser = currentUser, existingUser.firebaseUID == nil {
                // Migrate local user to Firebase
                try await migrateLocalUserToFirebase(localUser: existingUser, firebaseUID: firebaseUID, email: email)
            } else {
                // Load or create user from Firebase
                await loadOrCreateUserFromFirebase(firebaseUID: firebaseUID, email: email)
                
                // Add Apple as linked platform
                if let user = currentUser {
                    let platformInfo = LinkedPlatform(
                        platform: .apple,
                        platformUserId: firebaseUID,
                        linkedAt: .now,
                        email: email,
                        phoneNumber: nil,
                        displayName: finalDisplayName
                    )
                    
                    if !user.linkedPlatforms.contains(where: { $0.platform == .apple }) {
                        user.linkedPlatforms.append(platformInfo)
                    }
                    
                    try modelContext.save()
                    try await saveUserDataToFirestore(user)
                }
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020: // Account exists with different credential
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Link Apple account (for existing users)
    func linkAppleAccount() async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.networkError
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
                authorizationController.delegate = AppleSignInDelegate(continuation: continuation)
                authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
                authorizationController.performRequests()
            }
            
            guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.networkError
            }
            
            // Create OAuth credential for Apple Sign-In using nonce
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)

            
            let email = appleIDCredential.email
            let displayName = appleIDCredential.fullName.map { name in
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
            
            try await linkPlatformCredential(credential, platform: .apple, email: email, displayName: finalDisplayName)
        } catch {
            throw AuthError.networkError
        }
    }
    
    /// Link Microsoft account
    func linkMicrosoftAccount() async throws {
        guard currentUser != nil else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.networkError
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let provider = OAuthProvider(providerID: "microsoft.com")
        provider.scopes = ["openid", "email", "profile"]
        
        do {
            let credential = try await provider.credential(with: nil)
            try await linkPlatformCredential(credential, platform: .microsoft, email: nil, displayName: nil)
        } catch {
            throw AuthError.networkError
        }
    }
    
    /// Link Yahoo account
    func linkYahooAccount() async throws {
        guard currentUser != nil else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.networkError
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let provider = OAuthProvider(providerID: "yahoo.com")
        provider.scopes = ["openid", "email", "profile"]
        
        do {
            let credential = try await provider.credential(with: nil)
            try await linkPlatformCredential(credential, platform: .yahoo, email: nil, displayName: nil)
        } catch {
            throw AuthError.networkError
        }
    }
    
    /// Generic platform linking with credential
    private func linkPlatformCredential(_ credential: AuthCredential, platform: LinkedPlatform.PlatformType, email: String?, displayName: String?) async throws {
        guard let firebaseUser = auth.currentUser else {
            // If not authenticated with Firebase, create anonymous account first
            if let localUser = currentUser, localUser.firebaseUID == nil {
                let result = try await auth.signInAnonymously()
                await linkLocalUserToFirebase(localUser: localUser, firebaseUID: result.user.uid)
            } else {
                throw AuthError.noUser
            }
          return
        }
        
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        do {
            // Link the credential
            let result = try await auth.currentUser?.link(with: credential)
            let linkedUser = result?.user ?? auth.currentUser!
            
            // Extract user info
            var platformEmail = email
            var platformPhone: String? = nil
            var platformDisplayName = displayName
            
            for providerData in linkedUser.providerData {
                if providerData.providerID == credential.provider {
                    platformEmail = platformEmail ?? providerData.email
                    platformPhone = providerData.phoneNumber
                    platformDisplayName = platformDisplayName ?? providerData.displayName
                }
            }
            
            // Check username conflict
            if !user.isUsernameManuallyChanged {
                if try await isUsernameTaken(user.userName) {
                    await showUsernameConflictDialogForLinking(platform: platform)
                    try? await auth.currentUser?.unlink(fromProvider: credential.provider)
                    return
                }
            }
            
            // Create platform info
            let platformInfo = LinkedPlatform(
                platform: platform,
                platformUserId: linkedUser.uid,
                linkedAt: .now,
                email: platformEmail,
                phoneNumber: platformPhone,
                displayName: platformDisplayName
            )
            
            if !user.linkedPlatforms.contains(where: { $0.platform == platform }) {
                user.linkedPlatforms.append(platformInfo)
            }
            
            if let email = platformEmail, user.email == nil {
                user.email = email
            }
            if let phone = platformPhone, user.phoneNumber == nil {
                user.phoneNumber = phone
            }
            
            user.needsSync = true
            if let modelContext = modelContext {
                try modelContext.save()
            }
            
            if isOnline {
                try await saveUserDataToFirestore(user)
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17025:
                    throw AuthError.networkError
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Show username conflict dialog during linking
    private func showUsernameConflictDialogForLinking(platform: LinkedPlatform.PlatformType) async {
        conflictDialogMessage = "Your username '\(currentUser?.userName ?? "")' is already taken. Please choose a new username to link your \(platform.rawValue) account."
        conflictDialogNewUsername = ""
        showUsernameConflictDialog = true
        
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
                    Task { @MainActor in
                        self.errorMessage = "Account linking cancelled."
                    }
                }
            }
        }
    }
    
    /// Resolve username conflict
    func resolveUsernameConflict(newUsername: String?) {
        usernameConflictResolver?(newUsername)
    }
    
    /// Unlink a platform account
    func unlinkPlatform(_ platform: LinkedPlatform.PlatformType) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        guard let firebaseUser = auth.currentUser else {
            throw AuthError.noUser
        }
        
        let providerID: String
        switch platform {
        case .google: providerID = "google.com"
        case .apple: providerID = "apple.com"
        case .facebook: providerID = "facebook.com"
        case .twitter: providerID = "twitter.com"
        case .microsoft: providerID = "microsoft.com"
        case .yahoo: providerID = "yahoo.com"
        case .instagram: throw AuthError.notImplemented
        }
        
        if isOnline {
            do {
                try await firebaseUser.unlink(fromProvider: providerID)
            } catch {
                throw AuthError.networkError
            }
        }
        
        user.linkedPlatforms.removeAll { $0.platform == platform }
        user.needsSync = true
        
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        if isOnline {
            try await saveUserDataToFirestore(user)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthStateChange(_ user: User?) async {
        if let firebaseUser = user {
            guard let modelContext = modelContext else { return }
            await loadOrCreateUserFromFirebase(firebaseUID: firebaseUser.uid, email: firebaseUser.email)
        } else {
            // Firebase signed out, but keep local user
            if let localUser = currentUser {
                localUser.needsSync = true
                try? modelContext?.save()
            }
        }
    }
    
    // MARK: - Firestore Serialization
    
    private func firestoreDataFromAppUser(_ user: AppUser) -> [String: Any] {
        var data: [String: Any] = [
            "userName": user.userName,
            "createdAt": Timestamp(date: user.createdAt),
            "lastUpdated": Timestamp(date: user.lastUpdated),
            "avatarColor": user.avatarColor.rawValue,
            "avatarType": user.avatarType.rawValue,
            "isUsernameManuallyChanged": user.isUsernameManuallyChanged,
            "isEmailPublic": user.isEmailPublic,
            "isPhonePublic": user.isPhonePublic
        ]
        
        if let firstName = user.firstName {
            data["firstName"] = firstName
        }
        if let lastName = user.lastName {
            data["lastName"] = lastName
        }
        if let email = user.email {
            data["email"] = email
        }
        if let phoneNumber = user.phoneNumber {
            data["phoneNumber"] = phoneNumber
        }
        if let userImageURL = user.userImageURL {
            data["userImageURL"] = userImageURL
        }
        if let deviceIdentifier = user.deviceIdentifier {
            data["deviceIdentifier"] = deviceIdentifier
        }
        if let localIDBeforeFirebase = user.localIDBeforeFirebase {
            data["localIDBeforeFirebase"] = localIDBeforeFirebase
        }
        
        if !user.linkedPlatforms.isEmpty {
            data["linkedPlatforms"] = user.linkedPlatforms.map { platform in
                var platformData: [String: Any] = [
                    "platform": platform.platform.rawValue,
                    "platformUserId": platform.platformUserId,
                    "linkedAt": Timestamp(date: platform.linkedAt)
                ]
                if let email = platform.email {
                    platformData["email"] = email
                }
                if let phone = platform.phoneNumber {
                    platformData["phoneNumber"] = phone
                }
                if let displayName = platform.displayName {
                    platformData["displayName"] = displayName
                }
                return platformData
            }
        }
        
        return data
    }
    
    private func appUserFromFirestoreData(_ data: [String: Any], id: String) -> AppUser {
        let userName = data["userName"] as? String ?? "User"
        let firstName = data["firstName"] as? String
        let lastName = data["lastName"] as? String
        let email = data["email"] as? String
        let phoneNumber = data["phoneNumber"] as? String
        let userImageURL = data["userImageURL"] as? String
        let deviceIdentifier = data["deviceIdentifier"] as? String
        let isUsernameManuallyChanged = data["isUsernameManuallyChanged"] as? Bool ?? false
        let isEmailPublic = data["isEmailPublic"] as? Bool ?? false
        let isPhonePublic = data["isPhonePublic"] as? Bool ?? false
        let localIDBeforeFirebase = data["localIDBeforeFirebase"] as? String
        
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = .now
        }
        
        let lastUpdated: Date
        if let timestamp = data["lastUpdated"] as? Timestamp {
            lastUpdated = timestamp.dateValue()
        } else {
            lastUpdated = .now
        }
        
        let avatarColor: AvatarColor
        if let colorString = data["avatarColor"] as? String, let color = AvatarColor(rawValue: colorString) {
            avatarColor = color
        } else {
            avatarColor = AvatarColor.random()
        }
        
        let avatarType: AvatarType
        if let typeString = data["avatarType"] as? String, let type = AvatarType(rawValue: typeString) {
            avatarType = type
        } else {
            avatarType = AvatarType.random()
        }
        
        var linkedPlatforms: [LinkedPlatform] = []
        if let platformsArray = data["linkedPlatforms"] as? [[String: Any]] {
            for platformData in platformsArray {
                guard let platformString = platformData["platform"] as? String,
                      let platformType = LinkedPlatform.PlatformType(rawValue: platformString),
                      let platformUserId = platformData["platformUserId"] as? String else {
                    continue
                }
                
                let linkedAt: Date
                if let timestamp = platformData["linkedAt"] as? Timestamp {
                    linkedAt = timestamp.dateValue()
                } else {
                    linkedAt = .now
                }
                
                let platformEmail = platformData["email"] as? String
                let platformPhone = platformData["phoneNumber"] as? String
                let platformDisplayName = platformData["displayName"] as? String
                
                linkedPlatforms.append(LinkedPlatform(
                    platform: platformType,
                    platformUserId: platformUserId,
                    linkedAt: linkedAt,
                    email: platformEmail,
                    phoneNumber: platformPhone,
                    displayName: platformDisplayName
                ))
            }
        }
        
        return AppUser(
            id: id,
            userName: userName,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phoneNumber: phoneNumber,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            avatarColor: avatarColor,
            avatarType: avatarType,
            userImageURL: userImageURL,
            deviceIdentifier: deviceIdentifier,
            isUsernameManuallyChanged: isUsernameManuallyChanged,
            isEmailPublic: isEmailPublic,
            isPhonePublic: isPhonePublic,
            linkedPlatforms: linkedPlatforms,
            firebaseUID: id,
            lastSyncedToFirebase: .now,
            needsSync: false,
            localIDBeforeFirebase: localIDBeforeFirebase
        )
    }
}

// MARK: - Apple Sign In Helpers

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorization, Error>
    
    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}

private class AppleSignInPresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for Apple Sign In")
        }
        return window
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
    case noModelContext
    case emailAlreadyInUse
    case offline
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature is not yet available."
        case .noUser:
            return "No user is currently signed in."
        case .invalidCredentials:
            return "Invalid email or password."
        case .networkError:
            return "Unknown Network Error. Please try again later." // Should pass the data here, so we can print out the error.
        case .usernameTaken:
            return "This username is already taken. Please choose another."
        case .invalidUsername:
            return "Username cannot be empty."
        case .noModelContext:
            return "Model context is not available."
        case .emailAlreadyInUse:
            return "This email is already in use. Please sign in or use a different email."
        case .offline:
            return "You are offline. Please connect to the internet to perform this action."
        }
    }
}

