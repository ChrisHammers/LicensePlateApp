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
    @EnvironmentObject private var coordinator: MainSettingsCoordinator
    
    // Navigation
    
    // Keep local copies for editing
    @State private var currentUserName: String
    @State private var currentFirstName: String
    @State private var currentLastName: String
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCheckingUsername = false
    @State private var isUploadingImage = false
    @State private var linkingPlatform: LinkedPlatform.PlatformType? = nil
    @State private var showImagePicker = false
    @State private var showImageConfirmation = false
    @State private var selectedImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var showAvatarPickerSheet = false

    @StateObject private var lifetimeStatsViewModel: LifetimeStatsProfileViewModel
    @StateObject private var xpProgressViewModel: XpProgressViewModel
    @ObservedObject private var entitlementService = EntitlementService.shared
    @ObservedObject private var userProgressionRepository = UserProgressionRepository.shared
    @ObservedObject private var userProgressionService = UserProgressionService.shared

    // Helper function to get topmost view controller
    private func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
    
    // Helper function to handle platform linking
    private func handleLinkPlatform(_ platform: LinkedPlatform.PlatformType) {
        // Prevent multiple simultaneous taps
        guard !authService.isLoading, linkingPlatform == nil else {
            print("⚠️ Already linking, ignoring tap for \(platform.rawValue)")
            return
        }
        
        // Set the linking platform immediately
        linkingPlatform = platform
        
        Task {
            do {
                print("🔗 User tapped to link: \(platform.rawValue)")
                
                guard let presentingViewController = topViewController() else {
                    await MainActor.run {
                        errorMessage = "Unable to present sign in".localized
                        showError = true
                        linkingPlatform = nil
                    }
                    return
                }
                
                print("🔗 Calling link method for platform: \(platform.rawValue)")
                
                // Use explicit if-else instead of switch to prevent any fallthrough issues
                if platform == .google {
                    print("🔗 Linking Google account...")
                    try await authService.linkGoogleAccount(presentingViewController: presentingViewController)
                } else if platform == .apple {
                    print("🔗 Linking Apple account...")
                    try await authService.linkAppleAccount()
                } else if platform == .microsoft {
                    print("🔗 Linking Microsoft account...")
                    try await authService.linkMicrosoftAccount(presentingViewController: presentingViewController)
                } else if platform == .yahoo {
                    print("🔗 Linking Yahoo account...")
                    try await authService.linkYahooAccount(presentingViewController: presentingViewController)
                } else {
                    // Not yet implemented
                    print("❌ \(platform.rawValue) linking not implemented")
                    await MainActor.run {
                        errorMessage = "%@ linking is not yet available".localized(platform.rawValue)
                        showError = true
                        linkingPlatform = nil
                    }
                    return
                }
                
                print("✅ Successfully linked \(platform.rawValue)")
                
                // Clear linking platform on success
                await MainActor.run {
                    linkingPlatform = nil
                }
            } catch {
                print("❌ Error linking \(platform.rawValue): \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    linkingPlatform = nil
                }
            }
        }
    }
    
    init(user: AppUser, authService: FirebaseAuthService) {
        self.user = user
        self.authService = authService
        _currentUserName = State(initialValue: user.userName)
        _currentFirstName = State(initialValue: user.firstName ?? "")
        _currentLastName = State(initialValue: user.lastName ?? "")
        let lifetimeStatsVM = LifetimeStatsProfileViewModel(userId: user.id)
        let xpProgressVM = XpProgressViewModel(userId: user.id)
        _lifetimeStatsViewModel = StateObject(wrappedValue: lifetimeStatsVM)
        _xpProgressViewModel = StateObject(wrappedValue: xpProgressVM)
    }

    private var gameLicense: UserDriversLicense {
        let progression = userProgressionRepository.snapshot
        let effective = userProgressionService.effectiveTotals
        return UserDriversLicenseBuilder.make(from: ProfileLicenseInputs(
            user: user,
            lifetimeStats: lifetimeStatsViewModel.stats,
            totalXp: xpProgressViewModel.displayedTotalXp,
            acceptedRegionFindCount: effective?.acceptedRegionFindCount ?? progression?.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: effective?.competitiveFirstPlaceFinishes
                ?? progression?.competitiveFirstPlaceFinishes ?? 0,
            isRoyale: entitlementService.entitlementState(for: user).effectiveTier >= .royale
        ))
    }
    
    var body: some View {
            AppBackgroundView {
                List {
                    // Explorer license hero
                    Section {
                        ProfileDriversLicenseCardSection(
                            license: gameLicense,
                            user: user,
                            showsAvatarEdit: true,
                            onEditAvatar: {
                                let _ = print("I did it")
                                showAvatarPickerSheet = true
                                AnalyticsService.shared.log(.avatarPickerOpened(source: "profile"))
                            }
                        )

                        if isUploadingImage {
                            ProgressView("Uploading...".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    Section {
                        VStack(spacing: 12) {
                            // First Name - Editable
                            SettingEditableTextRow(
                                title: "First Name".localized,
                                value: $currentFirstName,
                                placeholder: "Enter first name".localized,
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
                                title: "Last Name".localized,
                                value: $currentLastName,
                                placeholder: "Enter last name".localized,
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
                                title: "Username".localized,
                                value: $currentUserName,
                                placeholder: "Enter username".localized,
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
                                title: "Email".localized,
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
                                        user.lastUpdated = .now
                                        try? modelContext.save()
                                        if authService.isTrulyAuthenticated {
                                            Task {
                                                try? await authService.saveUserDataToFirestore(user)
                                            }
                                        }
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
                                title: "Phone".localized,
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
                                        user.lastUpdated = .now
                                        try? modelContext.save()
                                        if authService.isTrulyAuthenticated {
                                            Task {
                                                try? await authService.saveUserDataToFirestore(user)
                                            }
                                        }
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
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Account Information".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))

                    LifetimeStatsProfileStatsSection(viewModel: lifetimeStatsViewModel)

                    ProfileXpProgressSection(viewModel: xpProgressViewModel)

                    Section {
                        VStack(spacing: 12) {
                            SettingNavigationRow(
                                title: "profile.progression.achievements.title".localized,
                                description: "profile.progression.achievements.description".localized,
                                icon: "rosette"
                            ) {
                                coordinator.navigateToAchievements()
                            }

                            SettingNavigationRow(
                                title: "profile.progression.ranks.title".localized,
                                description: "profile.progression.ranks.description".localized,
                                icon: "chart.line.uptrend.xyaxis"
                            ) {
                                coordinator.navifateToRankProgression()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("profile.progression.section_title".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))

                    // Friends & Family Section
                    Section {
                        VStack(spacing: 12) {
                            SettingNavigationRow(
                                title: "Friends".localized,
                                description: "Manage your friends and friend requests".localized,
                                icon: "person.2"
                            ) {
                                coordinator.navigateToFriends()
                            }

                            SettingNavigationRow(
                                title: "Family".localized,
                                description: "View and manage your family".localized,
                                icon: "house"
                            ) {
                                coordinator.navigateToFamily()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Friends & Family".localized)
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
                                      Text("Signed In".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Your account is synced to the cloud".localized)
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else if authService.wasPreviouslySignedIn {
                                      Text("Signed Out".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("You are signed out. Sign in to sync your account and access all features".localized)
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else if authService.isAnonymousUser || user.firebaseUID != nil {
                                      Text("Anonymous Account".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Sign up to sync your account and access more features".localized)
                                          .font(.system(.caption, design: .rounded))
                                          .foregroundStyle(Color.Theme.softBrown)
                                  } else {
                                      Text("Local Account".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                          .foregroundStyle(Color.Theme.primaryBlue)
                                      
                                      Text("Your account is stored locally only. Sign in to sync to the cloud".localized)
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
                                      Text("Sign In or Create Account".localized)
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
                                      Text("Sign Out".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                      
                                      Spacer()
                                      
                                      Image(systemName: "arrow.right")
                                          .font(.system(size: 14, weight: .semibold))
                                  }
                                  .foregroundStyle(Color.red)
                                  .padding(.vertical, 12)
                                  .padding(.horizontal, 16)
                                  .background(
                                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                                          .stroke(Color.red, lineWidth: 2)
                                  )
                              }
                          }
                          
                          // Sync status
                          if user.needsSync && !authService.isOnline {
                              HStack(spacing: 8) {
                                  Image(systemName: "arrow.clockwise")
                                      .font(.system(.caption, design: .rounded))
                                  Text("Changes will sync when you're online".localized)
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
                      Text("Authentication Status".localized)
                          .font(.system(.headline, design: .rounded))
                          .foregroundStyle(Color.Theme.primaryBlue)
                  }
                  .textCase(nil)
                  .listRowBackground(Color.clear)
                  .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                  
                    // MVP: Linked Accounts hidden — restore when account linking ships post-MVP
                    /*
                    // Linked Accounts Section
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            if user.linkedPlatforms.isEmpty {
                                Text("No accounts linked".localized)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            } else {
                                ForEach(user.linkedPlatforms, id: \.platform) { platform in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(platform.platform.rawValue)
                                                    .font(.system(.body, design: .rounded))
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(Color.Theme.primaryBlue)
                                                
                                                Spacer()
                                                
                                                Text("Linked".localized)
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.green)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule()
                                                            .fill(Color.green.opacity(0.15))
                                                    )
                                            }
                                            
                                            if let email = platform.email {
                                                Text("Email: %@".localized(email))
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                            }
                                            
                                            if let displayName = platform.displayName {
                                                Text("Name: %@".localized(displayName))
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                            }
                                        }
                                        
                                        // Unlink button
                                        Button {
                                            Task {
                                                do {
                                                    try await authService.unlinkPlatform(platform.platform)
                                                } catch {
                                                    errorMessage = error.localizedDescription
                                                    showError = true
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Color.red)
                                                .font(.system(size: 20))
                                        }
                                        .accessibilityLabel("Unlink %@ account".localized(platform.platform.rawValue))
                                        .accessibilityHint("Removes the linked %@ account".localized(platform.platform.rawValue))
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            
                            // Link new accounts section (only show if truly authenticated)
                            if authService.isTrulyAuthenticated {
                                Divider()
                                    .padding(.vertical, 8)
                                
                                Text("Link Additional Accounts".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .padding(.bottom, 4)
                                
                                // Available platforms to link (only show supported ones)
                                let supportedPlatforms: [LinkedPlatform.PlatformType] = [.google, .apple]//, .microsoft, .yahoo]
                                let availablePlatforms = supportedPlatforms.filter { platformType in
                                    !user.linkedPlatforms.contains(where: { $0.platform == platformType })
                                }
                                
                                if availablePlatforms.isEmpty {
                                    Text("All available accounts are linked".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(availablePlatforms, id: \.self) { platform in
                                            Button {
                                                handleLinkPlatform(platform)
                                            } label: {
                                                HStack {
                                                    Text("Link %@".localized(platform.rawValue))
                                                        .font(.system(.body, design: .rounded))
                                                        .fontWeight(.medium)
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.system(size: 18))
                                                        .accessibilityHidden(true)
                                                }
                                                .foregroundStyle(authService.isLoading ? Color.Theme.softBrown.opacity(0.7) : Color.Theme.primaryBlue)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(Color.Theme.primaryBlue.opacity(0.1))
                                                )
                                            }
                                            .disabled(authService.isLoading || linkingPlatform != nil)
                                            .accessibilityLabel("Link %@ account".localized(platform.rawValue))
                                            .accessibilityHint("Links your %@ account to this profile".localized(platform.rawValue))
                                            .accessibilityAddTraits(.isButton)
                                        }
                                    }
                                }
                            } else {
                                Text("Sign in to link additional accounts".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                    .italic()
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                    } header: {
                        Text("Linked Accounts".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    */
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Closes the profile view".localized)
                }
            }
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                lifetimeStatsViewModel.onAppear()
                xpProgressViewModel.refresh()
            }
            .onChange(of: user.userName) { oldValue, newValue in
                currentUserName = newValue
            }
            .sheet(isPresented: $authService.showSignInSheet) {
                SignInView(authService: authService, deferredSetupTouchSource: "profile")
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
            .sheet(isPresented: $showAvatarPickerSheet) {
                ProfileAvatarPickerSheet(
                    user: user,
                    onSave: {
                        try? modelContext.save()
                        Task { try? await authService.saveUserDataToFirestore(user) }
                        AnalyticsService.shared.log(.avatarSaved(avatarId: user.avatarId ?? "", source: "profile"))
                        showAvatarPickerSheet = false
                    },
                    onDismiss: { showAvatarPickerSheet = false }
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
    
    private func profileProgressionRow(title: String, description: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .accessibilityElement(children: .combine)
    }

    private func saveUserName() {
        let trimmedName = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Username cannot be empty".localized
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
                    errorMessage = "This username is already taken. Please choose another.".localized
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
            errorMessage = "You must be signed in to upload images. Please sign in first.".localized
            showError = true
            return
        }
        
        // Verify user is authenticated with Firebase
        guard Auth.auth().currentUser != nil else {
            errorMessage = "You must be authenticated with Firebase to upload images. Please sign in first.".localized
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
                    errorMessage = "Failed to upload image: %@".localized(errorDesc)
                    showError = true
                    isUploadingImage = false
                }
            }
        }
    }
}

// MARK: - Profile Avatar Picker Sheet

private struct ProfileAvatarPickerSheet: View {
    @Bindable var user: AppUser
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var selectedId: String?
    @State private var unlockSheetPayload: AvatarUnlockSheetPayload?
    @State private var showPaywallSheet = false
    @State private var paywallUnlockSource: AvatarUnlockSource?
    @StateObject private var paywallViewModel = PaywallViewModel()

    private let catalogService = AvatarCatalogService.shared
    
    private var displayItems: [AvatarDisplayItem] {
        catalogService.displayItems(for: user)
    }
    
    private var selectedAvatarDisplayName: String {
        guard let id = selectedId else { return "None".localized }
        return displayItems.first(where: { $0.id == id })?.displayName ?? "None".localized
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                VStack(spacing: 20) {
                    AvatarPickerView(
                        items: displayItems,
                        selectedId: $selectedId,
                        onLockedTap: { item, source in
                            unlockSheetPayload = AvatarUnlockSheetPayload(unlockSource: source, avatarName: item.displayName)
                        },
                        onSelected: nil
                    )
                    .frame(height: 196)
                    .padding()

                    VStack(spacing: 8) {
                        Text("Selected".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                        Text(selectedAvatarDisplayName)
                            .font(.headline)
                            .foregroundStyle(selectedAvatarDisplayName == "None".localized ? Color.Theme.softBrown : Color.Theme.primaryBlue)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Change avatar".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { onDismiss() }
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized) {
                        if let id = selectedId {
                            user.avatarId = id
                            user.lastUpdated = .now
                            onSave()
                        } else {
                            onDismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .onAppear {
                selectedId = user.avatarId ?? AvatarCatalog.guestAvatarIds.first
                DeferredProfileSetupStore.shared.markTouched(.avatar, source: "profile")
            }
            .overlay {
                if let payload = unlockSheetPayload {
                    AvatarUnlockPopupView(
                        unlockSource: payload.unlockSource,
                        avatarName: payload.avatarName,
                        onDismiss: { unlockSheetPayload = nil },
                        onShowPaywall: { source in
                            paywallUnlockSource = source
                            unlockSheetPayload = nil
                            showPaywallSheet = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showPaywallSheet) {
                PaywallView(viewModel: paywallViewModel, onDismiss: { showPaywallSheet = false })
                    .onAppear {
                        paywallViewModel.setUnlockContext(paywallUnlockSource)
                    }
            }
        }
    }
}

