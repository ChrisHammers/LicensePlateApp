//
//  UserProfileView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import GoogleSignInSwift
import FirebaseAuth

struct UserProfileView: View {
    @Bindable var user: AppUser
    @ObservedObject var authService: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Keep local copies for editing
    @State private var currentUserName: String
    @State private var currentFirstName: String
    @State private var currentLastName: String
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCheckingUsername = false
    @State private var isUploadingImage = false
    @State private var showImagePicker = false
    @State private var showImageConfirmation = false
    @State private var selectedImage: UIImage?
    @State private var previewImage: UIImage?
    
    init(user: AppUser, authService: FirebaseAuthService) {
        self.user = user
        self.authService = authService
        _currentUserName = State(initialValue: user.userName)
        _currentFirstName = State(initialValue: user.firstName ?? "")
        _currentLastName = State(initialValue: user.lastName ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    // Profile Image Section
                    Section {
                        VStack(spacing: 16) {
                            // User Image
                            Button {
                                showImagePicker = true
                            } label: {
                                ZStack {
                                    UserImageView(user: user, size: 120)
                                    
                                    // Edit overlay
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(8)
                                                .background(
                                                    Circle()
                                                        .fill(Color.Theme.primaryBlue)
                                                )
                                                .offset(x: -8, y: -8)
                                        }
                                    }
                                }
                            }
                            .disabled(isUploadingImage)
                            
                            if isUploadingImage {
                                ProgressView("Uploading...")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            
                            Text(user.displayName)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    Section {
                        // First Name - Editable
                        SettingEditableTextRow(
                            title: "First Name",
                            value: $currentFirstName,
                            placeholder: "Enter first name",
                            detail: nil,
                            isDisabled: false,
                            onSave: {
                                saveFirstName()
                            },
                            onCancel: {
                                cancelFirstNameEditing()
                            }
                        )
                        
                        // Last Name - Editable
                        SettingEditableTextRow(
                            title: "Last Name",
                            value: $currentLastName,
                            placeholder: "Enter last name",
                            detail: nil,
                            isDisabled: false,
                            onSave: {
                                saveLastName()
                            },
                            onCancel: {
                                cancelLastNameEditing()
                            }
                        )
                        
                        // Username - Editable
                        SettingEditableTextRow(
                            title: "Username",
                            value: $currentUserName,
                            placeholder: "Enter username",
                            detail: nil,
                            isDisabled: isCheckingUsername,
                            onSave: {
                                saveUserName()
                            },
                            onCancel: {
                                cancelEditing()
                            }
                        )
                      
                        // Email - Share Data Toggle
                        SettingShareDataToggleRow3(
                            title: "Email",
                            value: Binding(
                                get: { user.email },
                                set: { newValue in
                                    user.email = newValue
                                }
                            ),
                            detail: nil,
                            isOn: Binding(
                                get: { user.isEmailPublic },
                                set: { newValue in
                                    user.isEmailPublic = newValue
                                    try? modelContext.save()
                                }
                            ),
                            isEditable: false,
                            onSave: {
                                try? modelContext.save()
                            },
                            onCancel: {
                                // Reset to original value if needed
                            }
                        )
                        
                        // Phone - Share Data Toggle
                        SettingShareDataToggleRow3(
                            title: "Phone",
                            value: Binding(
                                get: { user.phoneNumber },
                                set: { newValue in
                                    user.phoneNumber = newValue
                                }
                            ),
                            detail: nil,
                            isOn: Binding(
                                get: { user.isPhonePublic },
                                set: { newValue in
                                    user.isPhonePublic = newValue
                                    try? modelContext.save()
                                }
                            ),
                            isEditable: true,
                            onSave: {
                                try? modelContext.save()
                            },
                            onCancel: {
                                // Reset to original value if needed
                            }
                        )
                        
                    } header: {
                        Text("Account Information")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                  // Authentication Status Section
                  Section {
                      VStack(alignment: .leading, spacing: 16) {
                          // Authentication status
                          HStack {
                              VStack(alignment: .leading, spacing: 4) {
                                  if authService.isTrulyAuthenticated {
                                      Text("Signed In")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Your account is synced to the cloud")
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else if authService.wasPreviouslySignedIn {
                                      Text("Signed Out")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("You are signed out. Sign in to sync your account and access all features")
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else if authService.isAnonymousUser || user.firebaseUID != nil {
                                      Text("Anonymous Account")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Sign up to sync your account and access more features")
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else {
                                      Text("Local Account")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Your account is stored locally only. Sign in to sync to the cloud")
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  }
                              }
                              
                              Spacer()
                              
                              if authService.isTrulyAuthenticated {
                                  Image(systemName: "checkmark.circle.fill")
                                      .foregroundStyle(.green)
                              } else {
                                  Image(systemName: "exclamationmark.circle.fill")
                                      .foregroundStyle(Color.Theme.accentYellow)
                              }
                          }
                          
                          // Sign in / Create account button (show if NOT truly authenticated)
                          if !authService.isTrulyAuthenticated {
                              Button {
                                  authService.showSignInSheet = true
                              } label: {
                                  HStack {
                                      Text("Sign In or Create Account")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                      
                                      Spacer()
                                      
                                      Image(systemName: "arrow.right")
                                          .font(.system(size: 14, weight: .semibold))
                                  }
                                  .foregroundStyle(.white)
                                  .padding(.vertical, 12)
                                  .padding(.horizontal, 16)
                                  .background(
                                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                                          .fill(Color.Theme.primaryBlue)
                                  )
                              }
                          } else {
                              // Sign out button (only show if truly authenticated)
                              Button {
                                  Task {
                                      do {
                                          try await authService.signOut()
                                      } catch {
                                          errorMessage = error.localizedDescription
                                          showError = true
                                      }
                                  }
                              } label: {
                                  HStack {
                                      Text("Sign Out")
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                      
                                      Spacer()
                                      
                                      Image(systemName: "arrow.right")
                                          .font(.system(size: 14, weight: .semibold))
                                  }
                                  .foregroundStyle(Color.Theme.primaryBlue)
                                  .padding(.vertical, 12)
                                  .padding(.horizontal, 16)
                                  .background(
                                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                                          .stroke(Color.Theme.primaryBlue, lineWidth: 2)
                                  )
                              }
                          }
                          
                          // Sync status
                          if user.needsSync && !authService.isOnline {
                              HStack(spacing: 8) {
                                  Image(systemName: "arrow.clockwise")
                                      .font(.system(.caption, design: .rounded))
                                  Text("Changes will sync when you're online")
                                      .font(.system(.caption, design: .rounded))
                              }
                              .foregroundStyle(Color.Theme.softBrown)
                              .padding(.top, 8)
                          }
                      }
                      .padding(.vertical, 12)
                      .padding(.horizontal, 16)
                      .background(
                          RoundedRectangle(cornerRadius: 20, style: .continuous)
                              .fill(Color.Theme.cardBackground)
                      )
                  } header: {
                      Text("Authentication Status")
                          .font(.system(.headline, design: .rounded))
                          .foregroundStyle(Color.Theme.primaryBlue)
                  }
                  .textCase(nil)
                  .listRowBackground(Color.clear)
                  .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                  
                    // Linked Accounts Section
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            if user.linkedPlatforms.isEmpty {
                                Text("No accounts linked")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            } else {
                                ForEach(user.linkedPlatforms, id: \.platform) { platform in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(platform.platform.rawValue)
                                                .font(.system(.body, design: .rounded))
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.Theme.primaryBlue)
                                            
                                            Spacer()
                                            
                                            Text("Linked")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown)
                                        }
                                        
                                        if let email = platform.email {
                                            Text("Email: \(email)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                        
                                        if let phone = platform.phoneNumber {
                                            Text("Phone: \(phone)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                        
                                        if let displayName = platform.displayName {
                                            Text("Name: \(displayName)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            
                            // Placeholder for future platform linking buttons
                            Text("Platform linking coming soon")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                .italic()
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                    } header: {
                        Text("Linked Accounts")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: user.userName) { oldValue, newValue in
                currentUserName = newValue
            }
            .sheet(isPresented: $authService.showSignInSheet) {
                SignInView(authService: authService)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showImageConfirmation) {
                ImageConfirmationView(
                    image: previewImage,
                    onUse: {
                        if let image = previewImage {
                            uploadUserImage(image)
                        }
                        showImageConfirmation = false
                        previewImage = nil
                    },
                    onCancel: {
                        showImageConfirmation = false
                        previewImage = nil
                        selectedImage = nil
                    }
                )
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let newImage = newValue {
                    // Show confirmation instead of immediately uploading
                    previewImage = newImage
                    showImageConfirmation = true
                }
            }
            .onChange(of: user.firstName) { oldValue, newValue in
                currentFirstName = newValue ?? ""
            }
            .onChange(of: user.lastName) { oldValue, newValue in
                currentLastName = newValue ?? ""
            }
        }
        .background(Color.Theme.background)
    }
    
    private func saveUserName() {
        let trimmedName = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Username cannot be empty"
            showError = true
            currentUserName = user.userName // Reset to original
            return
        }
        
        guard trimmedName != user.userName else {
            return // No change needed
        }
        
        // Check username uniqueness
        isCheckingUsername = true
        Task {
            do {
                // Check if username is taken
                let isTaken = try await authService.isUsernameTaken(trimmedName)
                
                if isTaken {
                    errorMessage = "This username is already taken. Please choose another."
                    showError = true
                    currentUserName = user.userName // Reset to original
                    isCheckingUsername = false
                    return
                }
                
                // Update in auth service (which also checks uniqueness)
                try await authService.updateUserName(trimmedName)
                
                // Save to SwiftData
                try modelContext.save()
                
                isCheckingUsername = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                currentUserName = user.userName // Reset to original
                isCheckingUsername = false
            }
        }
    }
    
    private func cancelEditing() {
        currentUserName = user.userName // Reset to original
    }
    
    private func saveFirstName() {
        let trimmed = currentFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        user.firstName = trimmed.isEmpty ? nil : trimmed
        user.lastUpdated = .now
        try? modelContext.save()
        
        // Sync to Firestore if authenticated
        if authService.isTrulyAuthenticated {
            Task {
                try? await authService.saveUserDataToFirestore(user)
            }
        }
    }
    
    private func cancelFirstNameEditing() {
        currentFirstName = user.firstName ?? ""
    }
    
    private func saveLastName() {
        let trimmed = currentLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        user.lastName = trimmed.isEmpty ? nil : trimmed
        user.lastUpdated = .now
        try? modelContext.save()
        
        // Sync to Firestore if authenticated
      if authService.isTrulyAuthenticated {
            Task {
                try? await authService.saveUserDataToFirestore(user)
            }
        }
    }
    
    private func cancelLastNameEditing() {
        currentLastName = user.lastName ?? ""
    }
    
  
  func optimizedImage(_ originalImage: UIImage) -> Data? {
    let scaledImage = scaleImageIfNeeded(originalImage)
    let compression: CGFloat = 0.8 // 80% quality
    let imageData = scaledImage.jpegData(compressionQuality: compression)
    return imageData
  }
  
  private func scaleImageIfNeeded(_ image: UIImage) -> UIImage {
    let size = image.size
    
    // If image is smaller than max dimension, return original
    if size.width <= 300 && size.height <= 300 {
      return image
    }
    
    // Calculate aspect ratio
    let aspectRatio = size.width / size.height
    
    // Calculate new size while maintaining aspect ratio
    var newSize: CGSize
    if size.width > size.height {
      newSize = CGSize(width: 300, height: 300 / aspectRatio)
    } else {
      newSize = CGSize(width: 300 * aspectRatio, height: 300)
    }
    
    // Scale down the image
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { context in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  
    private func uploadUserImage(_ image: UIImage) {
        // Must use Firebase UID for Storage (not local ID)
        guard let firebaseUID = user.firebaseUID else {
            errorMessage = "You must be signed in to upload images. Please sign in first."
            showError = true
            return
        }
        
        // Verify user is authenticated with Firebase
        guard Auth.auth().currentUser != nil else {
            errorMessage = "You must be authenticated with Firebase to upload images. Please sign in first."
            showError = true
            return
        }
        
        isUploadingImage = true
        
        Task {
            do {
                // Compress image to JPEG
                guard let imageData = optimizedImage(image) else {
                    throw NSError(domain: "ImageUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
                }
                
                print("📤 Uploading image for Firebase user: \(firebaseUID)")
                print("📤 Image size after compression: \(imageData.count) bytes")
                
                // Upload to Firebase Storage (must use Firebase UID)
                let storageService = FirebaseStorageService()
                let imageURL = try await storageService.uploadUserImage(userId: firebaseUID, imageData: imageData)
                
                // Update user
                await MainActor.run {
                    user.userImageURL = imageURL
                    user.lastUpdated = .now
                    
                    // Clear old cache
                    UserImageCache.shared.deleteCachedImage(for: firebaseUID)
                    
                    // Save to cache
                    UserImageCache.shared.saveImage(imageData, for: firebaseUID)
                    
                    try? modelContext.save()
                    isUploadingImage = false
                }
                
                // Sync to Firestore
                try await authService.saveUserDataToFirestore(user)
                
            } catch {
                await MainActor.run {
                    let errorDesc = error.localizedDescription
                    print("❌ Image upload failed: \(errorDesc)")
                    if let nsError = error as NSError? {
                        print("   Error domain: \(nsError.domain)")
                        print("   Error code: \(nsError.code)")
                        print("   Error userInfo: \(nsError.userInfo)")
                    }
                    errorMessage = "Failed to upload image: \(errorDesc)"
                    showError = true
                    isUploadingImage = false
                }
            }
        }
    }
}

