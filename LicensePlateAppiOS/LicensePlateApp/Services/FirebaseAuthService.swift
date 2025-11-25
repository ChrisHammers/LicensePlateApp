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
import CoreLocation

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

/// Firebase Authentication Service - Simplified flow
/// 1. On app startup: Create default user, sign in anonymously if online
/// 2. User can upgrade anonymous account by linking credentials (email/password, OAuth)
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
    
    // Store location delegates to prevent deallocation
    var activeLocationDelegates: [OneTimeLocationDelegate] = []
    
    // Track last login tracking time to prevent duplicates
    private var lastLoginTrackingTime: Date?
    
    init() {
        // Observe auth state changes
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
    
    var isOnline: Bool {
        networkMonitor.isConnected
    }
    
    // MARK: - Initialization
    
    /// Initialize authentication state (call on app startup)
    func initializeAuthState(modelContext: ModelContext) async {
        self.modelContext = modelContext
        
        // Check if Firebase Auth already has a user (persisted session)
        if let firebaseUser = auth.currentUser {
            // Firebase has a user, load it
            await loadUserFromFirebase(firebaseUser)
        } else {
            // No Firebase user, check for local user by device
            let deviceId = DeviceIdentifier.getDeviceIdentifier()
            let descriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { $0.deviceIdentifier == deviceId }
            )
            
            if let existingUser = try? modelContext.fetch(descriptor).first {
                // Found existing user, set as current
                currentUser = existingUser
                isAuthenticated = true
                
                // If online and user has firebaseUID, try to restore Firebase session
                if isOnline, let firebaseUID = existingUser.firebaseUID {
                    // Try to load from Firestore
                    Task {
                        try? await loadUserDataFromFirestore(userId: firebaseUID)
                    }
                } else if isOnline, existingUser.firebaseUID == nil {
                    // User exists locally but no Firebase account - sign in anonymously
                    Task {
                        try? await signInAnonymously()
                    }
                }
            } else {
                // No user exists, create default user
                try? await createDefaultUser()
            }
        }
    }
    
    // MARK: - Default User Creation
    
    /// Create default user with device-based username
    private func createDefaultUser() async throws {
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        let defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        
        // Create local user first
        let localID = UUID().uuidString
        let newUser = AppUser(
            id: localID,
            userName: defaultUsername,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: false,
            needsSync: true
        )
        
        modelContext.insert(newUser)
        try modelContext.save()
        
        currentUser = newUser
        isAuthenticated = true
        
        // If online, immediately sign in anonymously
        if isOnline {
            Task {
                try? await signInAnonymously()
            }
        }
    }
    
    // MARK: - Anonymous Authentication
    
    /// Sign in anonymously (creates Firebase anonymous account and links to local user)
    func signInAnonymously() async throws {
        guard let modelContext = modelContext,
              let localUser = currentUser else {
            throw AuthError.noUser
        }
        
        // If user already has firebaseUID, don't create new anonymous account
        if localUser.firebaseUID != nil {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            // Offline - mark for sync later
            localUser.needsSync = true
            try? modelContext.save()
            return
        }
        
        do {
            let result = try await auth.signInAnonymously()
            let firebaseUID = result.user.uid
            
            // Link local user to Firebase anonymous account
            localUser.firebaseUID = firebaseUID
            localUser.id = firebaseUID // Update ID to Firebase UID
            localUser.needsSync = false
            
            try modelContext.save()
            
            // Save to Firestore
            try await saveUserDataToFirestore(localUser)
            
            currentUser = localUser
            isAuthenticated = true
        } catch {
            print("⚠️ Anonymous sign-in failed: \(error)")
            // Continue with local user
            localUser.needsSync = true
            try? modelContext.save()
        }
    }
    
    // MARK: - Username Uniqueness Checking
    
    func isUsernameTakenLocally(_ username: String, excludingUserId: String? = nil) async throws -> Bool {
        guard let modelContext = modelContext else { return false }
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.userName == username }
        )
        let users = try? modelContext.fetch(descriptor)
        
        guard let users = users, !users.isEmpty else {
            return false
        }
        
        if let excludingID = excludingUserId {
            let otherUsers = users.filter { $0.id != excludingID && $0.firebaseUID != excludingID }
            return !otherUsers.isEmpty
        }
        
        return true
    }
    
    func isUsernameTaken(_ username: String, excludingUserId: String? = nil) async throws -> Bool {
        // Check local first
        if try await isUsernameTakenLocally(username, excludingUserId: excludingUserId) {
            return true
        }
        
        // Check Firebase if online
        guard isOnline else {
            return false
        }
        
        do {
            let usersRef = db.collection("users")
            let query = usersRef.whereField("userName", isEqualTo: username).limit(to: 1)
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                return false
            }
            
            if let excludingUID = excludingUserId {
                let matchingDocs = snapshot.documents.filter { doc in
                    doc.documentID != excludingUID
                }
                return !matchingDocs.isEmpty
            }
            
            return true
        } catch {
            print("⚠️ Firebase username check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Authentication Status
    
    var isTrulyAuthenticated: Bool {
        guard let firebaseUser = auth.currentUser else {
            return false
        }
        return !firebaseUser.isAnonymous
    }
    
    var isAnonymousUser: Bool {
        guard let firebaseUser = auth.currentUser else {
            return currentUser?.firebaseUID != nil && !isTrulyAuthenticated
        }
        return firebaseUser.isAnonymous
    }
    
    var wasPreviouslySignedIn: Bool {
        guard let user = currentUser else { return false }
        return user.firebaseUID != nil && !isAuthenticated && !isAnonymousUser
    }
    
    // MARK: - Sign In / Create Account
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            await loadUserFromFirebase(result.user)
            // updateLoginTracking is called in loadUserFromFirebase
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
    
    /// Create account with email and password (upgrades anonymous if exists)
    func createAccount(
        email: String,
        password: String,
        userName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        phoneNumber: String? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard let modelContext = modelContext,
              let currentUser = currentUser else {
            throw AuthError.noUser
        }
        
        // Check username uniqueness (exclude current user)
        let excludingId = currentUser.firebaseUID ?? currentUser.id
        guard try await !isUsernameTaken(userName, excludingUserId: excludingId) else {
            throw AuthError.usernameTaken
        }
        
        do {
            // Check if current user is anonymous
            if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                // Link email/password to anonymous account
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                
                do {
                    let result = try await firebaseUser.link(with: credential)
                    // Update user info
                    currentUser.email = email
                    currentUser.userName = userName
                    currentUser.firstName = firstName
                    currentUser.lastName = lastName
                    currentUser.phoneNumber = phoneNumber
                    currentUser.isUsernameManuallyChanged = true
                    
                    try modelContext.save()
                    try await saveUserDataToFirestore(currentUser)
                    
                    isAuthenticated = true
                    
                    // Update login tracking
                    await updateLoginTracking()
                } catch {
                    // If linking fails (email already in use), create new account
                    try auth.signOut()
                    let result = try await auth.createUser(withEmail: email, password: password)
                    await createNewUserFromFirebase(result.user, email: email, userName: userName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber)
                    
                    // Update login tracking
                    await updateLoginTracking()
                }
            } else {
                // Not anonymous, create new account
                let result = try await auth.createUser(withEmail: email, password: password)
                await createNewUserFromFirebase(result.user, email: email, userName: userName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber)
                
                // Update login tracking
                await updateLoginTracking()
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
    
    /// Sign out (keeps local user, clears Firebase auth)
    func signOut() async throws {
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        if isOnline {
            do {
                try auth.signOut()
            } catch {
                print("⚠️ Firebase sign out failed: \(error)")
            }
        }
        
        // Keep user data, just mark as signed out
        if let user = currentUser {
            user.linkedPlatforms.removeAll()
            user.needsSync = false
            // Keep firebaseUID for future sign-in
            try modelContext.save()
        }
        
        isAuthenticated = false
    }
    
    // MARK: - OAuth Sign In
    
    /// Sign in with Google
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
            
          // Check if anonymous, link if so
                     if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                         let result = try await firebaseUser.link(with: credential)
                         await updateUserFromOAuth(result.user, email: googleUser.profile?.email, displayName: googleUser.profile?.name)
                         // Update login tracking
                         await updateLoginTracking()
                     } else {
                let authResult = try await auth.signIn(with: credential)
                await loadUserFromFirebase(authResult.user)
                // updateLoginTracking is called in loadUserFromFirebase
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020:
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Sign in with Apple
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
            
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
            
            let email = appleIDCredential.email
            let displayName = appleIDCredential.fullName.map { name in
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
            
          // Check if anonymous, link if so
                     if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                         let result = try await firebaseUser.link(with: credential)
                         await updateUserFromOAuth(result.user, email: email, displayName: finalDisplayName)
                         // Update login tracking
                         await updateLoginTracking()
                     } else {
                let authResult = try await auth.signIn(with: credential)
                await loadUserFromFirebase(authResult.user)
                // updateLoginTracking is called in loadUserFromFirebase
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020:
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    // MARK: - Platform Linking (for existing authenticated users)
    
    func linkGoogleAccount(presentingViewController: UIViewController) async throws {
        guard let user = currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLoading = true
        defer { isLoading = false }
        
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
    }
    
    func linkAppleAccount() async throws {
        guard let user = currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
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
        
        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
        
        let email = appleIDCredential.email
        let displayName = appleIDCredential.fullName.map { name in
            let given = name.givenName ?? ""
            let family = name.familyName ?? ""
            return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
        }
        let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
        
        try await linkPlatformCredential(credential, platform: .apple, email: email, displayName: finalDisplayName)
    }
    
    func linkMicrosoftAccount() async throws {
        guard currentUser != nil, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let provider = OAuthProvider(providerID: "microsoft.com")
        provider.scopes = ["openid", "email", "profile"]
        
        let credential = try await provider.credential(with: nil)
        try await linkPlatformCredential(credential, platform: .microsoft, email: nil, displayName: nil)
    }
    
    func linkYahooAccount() async throws {
        guard currentUser != nil, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let provider = OAuthProvider(providerID: "yahoo.com")
        provider.scopes = ["openid", "email", "profile"]
        
        let credential = try await provider.credential(with: nil)
        try await linkPlatformCredential(credential, platform: .yahoo, email: nil, displayName: nil)
    }
    
  private func linkPlatformCredential(_ credential: AuthCredential, platform: LinkedPlatform.PlatformType, email: String?, displayName: String?) async throws {
         guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
             throw AuthError.noUser
         }
         
         guard let user = currentUser, let modelContext = modelContext else {
             throw AuthError.noUser
         }
         
         do {
             let result = try await firebaseUser.link(with: credential)
             let linkedUser = result.user
             
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
             
             // Check username conflict (only if username wasn't manually changed)
             if !user.isUsernameManuallyChanged {
                 let excludingId = user.firebaseUID ?? user.id
                 if try await isUsernameTaken(user.userName, excludingUserId: excludingId) {
                     await showUsernameConflictDialogForLinking(platform: platform)
                     try? await firebaseUser.unlink(fromProvider: credential.provider)
                     return
                 }
             }
             
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
             
             try modelContext.save()
             try await saveUserDataToFirestore(user)
         } catch {
             throw AuthError.networkError
         }
     }
     
     /// Show username conflict dialog during linking
     private func showUsernameConflictDialogForLinking(platform: LinkedPlatform.PlatformType) async {
         guard let user = currentUser else { return }
         
         conflictDialogMessage = "Your username '\(user.userName)' is already taken. Please choose a new username to link your \(platform.rawValue) account."
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
                             // Retry linking after username update
                             // Note: This would need to be handled by the caller
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
    // MARK: - User Management
    
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
        
        let excludingId = user.firebaseUID ?? user.id
        guard try await !isUsernameTaken(trimmedName, excludingUserId: excludingId) else {
            throw AuthError.usernameTaken
        }
        
        user.updateUserName(trimmedName, isManual: true)
        user.needsSync = true
        
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        if isOnline {
            Task {
                try? await saveUserDataToFirestore(user)
            }
        }
    }
  
  /// Resolve username conflict
     func resolveUsernameConflict(newUsername: String?) {
         usernameConflictResolver?(newUsername)
     }
    
    /// Update login tracking (date and location if available)
    private func updateLoginTracking() async {
        guard let user = currentUser,
              let modelContext = modelContext else {
            return
        }
        
        // Debounce: Only track if it's been more than 5 seconds since last tracking
        if let lastTracking = lastLoginTrackingTime,
           Date().timeIntervalSince(lastTracking) < 5.0 {
            // Too soon since last tracking, skip
            return
        }
        
        // Update last tracking time
        lastLoginTrackingTime = .now
        
        // Always update last login date
        user.lastDateLoggedIn = .now
        
        // Check location permission and update location if available
        let locationManager = CLLocationManager()
        let authStatus = locationManager.authorizationStatus
        
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            // Location is authorized, try to get current location
            if let location = await getCurrentLocation() {
                let loginLocation = LoginLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                
                // Add new location and keep only last 5
                user.lastLoginLocation.append(loginLocation)
                if user.lastLoginLocation.count > 5 {
                    user.lastLoginLocation.removeFirst()
                }
            }
        }
        // If location not authorized, silently skip (don't ask user)
        
        try? modelContext.save()
        user.needsSync = true
        
        // Sync to Firestore if online
        if isOnline {
            Task {
                try? await saveUserDataToFirestore(user)
            }
        }
    }
    
    /// Get current location (one-time request)
    private func getCurrentLocation() async -> CLLocation? {
        return await withCheckedContinuation { continuation in
            let locationManager = CLLocationManager()
            let authStatus = locationManager.authorizationStatus
            
            guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
                continuation.resume(returning: nil)
                return
            }
            
            // Create delegate with reference to self for cleanup
            let delegate = OneTimeLocationDelegate(service: self) { location in
                continuation.resume(returning: location)
            }
            
            // Store delegate to keep it alive
            activeLocationDelegates.append(delegate)
            
            locationManager.delegate = delegate
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthStateChange(_ user: User?) async {
        if let firebaseUser = user {
            await loadUserFromFirebase(firebaseUser)
        } else {
            // Firebase signed out
            isAuthenticated = false
        }
    }
    
    private func loadUserFromFirebase(_ firebaseUser: User) async {
        guard let modelContext = modelContext else { return }
        
        let firebaseUID = firebaseUser.uid
        
        // Check if user exists locally
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.firebaseUID == firebaseUID || $0.id == firebaseUID }
        )
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            // Update user's id to firebaseUID if needed
            if existingUser.id != firebaseUID {
                existingUser.id = firebaseUID
            }
            existingUser.firebaseUID = firebaseUID
            try? modelContext.save()
            
            currentUser = existingUser
            isAuthenticated = true
            
            // Update login tracking
            await updateLoginTracking()
            
            // Load from Firestore to get latest data
            Task {
                if let firestoreUser = try? await loadUserDataFromFirestore(userId: firebaseUID) {
                    // Merge Firestore data with local user
                    existingUser.userName = firestoreUser.userName
                    existingUser.firstName = firestoreUser.firstName
                    existingUser.lastName = firestoreUser.lastName
                    existingUser.email = firestoreUser.email
                    existingUser.phoneNumber = firestoreUser.phoneNumber
                    existingUser.userImageURL = firestoreUser.userImageURL
                    existingUser.linkedPlatforms = firestoreUser.linkedPlatforms
                    try? modelContext.save()
                }
            }
        } else {
            // Load from Firestore or create new
            if let firestoreUser = try? await loadUserDataFromFirestore(userId: firebaseUID) {
                modelContext.insert(firestoreUser)
                try? modelContext.save()
                currentUser = firestoreUser
                isAuthenticated = true
                
                // Update login tracking
                await updateLoginTracking()
            } else {
                // Create new user from Firebase auth
                await createNewUserFromFirebase(firebaseUser, email: firebaseUser.email, userName: nil, firstName: nil, lastName: nil, phoneNumber: nil)
                
                // Update login tracking
                await updateLoginTracking()
            }
        }
    }
    
    private func createNewUserFromFirebase(_ firebaseUser: User, email: String?, userName: String?, firstName: String?, lastName: String?, phoneNumber: String?) async {
        guard let modelContext = modelContext else { return }
        
        let firebaseUID = firebaseUser.uid
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        let defaultUsername = userName ?? DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        
        let newUser = AppUser(
            id: firebaseUID,
            userName: defaultUsername,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phoneNumber: phoneNumber,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: userName != nil,
            firebaseUID: firebaseUID
        )
        
        modelContext.insert(newUser)
        try? modelContext.save()
        
        currentUser = newUser
        isAuthenticated = true
        
        // Save to Firestore
        Task {
            try? await saveUserDataToFirestore(newUser)
        }
    }
    
    private func updateUserFromOAuth(_ firebaseUser: User, email: String?, displayName: String?) async {
        guard let modelContext = modelContext,
              let user = currentUser else { return }
        
        // Update user info from OAuth
        if let email = email, user.email == nil {
            user.email = email
        }
        
        if let displayName = displayName {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                user.firstName = components[0]
                user.lastName = components.dropFirst().joined(separator: " ")
            } else {
                user.firstName = displayName
            }
        }
        
        try? modelContext.save()
        try? await saveUserDataToFirestore(user)
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
    
    func saveUserDataToFirestore(_ user: AppUser) async throws {
        guard isOnline else {
            user.needsSync = true
            try? modelContext?.save()
            return
        }
        
        guard let firebaseUID = user.firebaseUID else {
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
        if let lastDateLoggedIn = user.lastDateLoggedIn {
            data["lastDateLoggedIn"] = Timestamp(date: lastDateLoggedIn)
        }
        if !user.lastLoginLocation.isEmpty {
            data["lastLoginLocation"] = user.lastLoginLocation.map { location in
                [
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "timestamp": Timestamp(date: location.timestamp)
                ]
            }
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
        
        let lastDateLoggedIn: Date?
        if let timestamp = data["lastDateLoggedIn"] as? Timestamp {
            lastDateLoggedIn = timestamp.dateValue()
        } else {
            lastDateLoggedIn = nil
        }
        
        var lastLoginLocation: [LoginLocation] = []
        if let locationsArray = data["lastLoginLocation"] as? [[String: Any]] {
            for locationData in locationsArray {
                guard let latitude = locationData["latitude"] as? Double,
                      let longitude = locationData["longitude"] as? Double else {
                    continue
                }
                
                let timestamp: Date
                if let ts = locationData["timestamp"] as? Timestamp {
                    timestamp = ts.dateValue()
                } else {
                    timestamp = .now
                }
                
                lastLoginLocation.append(LoginLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                ))
            }
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
            lastDateLoggedIn: lastDateLoggedIn,
            lastLoginLocation: lastLoginLocation
        )
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
}

// MARK: - One-Time Location Helper
 class OneTimeLocationDelegate: NSObject, CLLocationManagerDelegate {
    private weak var service: FirebaseAuthService?
    private let completion: (CLLocation?) -> Void
    
    init(service: FirebaseAuthService, completion: @escaping (CLLocation?) -> Void) {
        self.service = service
        self.completion = completion
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
        completion(locations.first)
        // Remove self from service's delegate array
        service?.activeLocationDelegates.removeAll { $0 === self }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        completion(nil)
        // Remove self from service's delegate array
        service?.activeLocationDelegates.removeAll { $0 === self }
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
            return "Unknown Network Error. Please try again later."
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
