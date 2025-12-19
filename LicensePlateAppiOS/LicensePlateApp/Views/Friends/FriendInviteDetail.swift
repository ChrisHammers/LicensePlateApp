//
//  FriendInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct FriendInviteDetail: View {
    let inviteId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let friendshipRepository = FriendshipRepository.shared
    @State private var isProcessing = false
    @State private var hasAccepted = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var user: AppUser?
    @State private var isLoadingUser = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    if isLoadingUser {
                        ProgressView()
                            .padding()
                    } else if let user = user {
                        // User Avatar
                        UserImageView(user: user, size: 100)
                        
                        // User Name
                        Text(user.displayName)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        // Username
                        Text("@\(user.userName)")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    } else {
                        Text("Friend Request".localized)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    
                    if hasAccepted {
                        VStack(spacing: 12) {
                            Text("Friend request accepted!".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            Text("You are now friends".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                        }
                        .padding()
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Done".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        Button {
                            respondToInvite(accept: true)
                        } label: {
                            Text("Accept".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                        
                        Button {
                            respondToInvite(accept: false)
                        } label: {
                            Text("Decline".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                    }
                    
                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .navigationTitle("Friend Invite".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                friendshipRepository.setModelContext(modelContext)
            }
            .task {
                await loadInviteAndUser()
            }
        }
    }
    
    private func loadInviteAndUser() async {
        isLoadingUser = true
        
        // First try to get invite from SwiftData
        let searchInviteId = inviteId
        let inviteDescriptor = FetchDescriptor<Invite>(
            predicate: #Predicate<Invite> { invite in
                invite.inviteId == searchInviteId
            }
        )
        
        var fromUserId: String?
        
        if let cachedInvite = try? modelContext.fetch(inviteDescriptor).first {
            fromUserId = cachedInvite.fromUserId
        } else {
            // If not in cache, fetch from Firestore
            let db = Firestore.firestore()
            do {
                let inviteDoc = try await db.collection("invites").document(inviteId).getDocument()
                if let data = inviteDoc.data() {
                    fromUserId = data["fromUserId"] as? String
                }
            } catch {
                print("⚠️ Failed to fetch invite \(inviteId): \(error.localizedDescription)")
                await MainActor.run {
                    isLoadingUser = false
                }
                return
            }
        }
        
        guard let userId = fromUserId else {
            await MainActor.run {
                isLoadingUser = false
            }
            return
        }
        
        // Fetch user data
        await loadUser(userId: userId)
    }
    
    private func loadUser(userId: String) async {
        // First try to get from SwiftData cache
        let searchUserId = userId
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { user in
                user.id == searchUserId || user.firebaseUID == searchUserId
            }
        )
        
        if let cachedUser = try? modelContext.fetch(descriptor).first {
            await MainActor.run {
                self.user = cachedUser
                self.isLoadingUser = false
            }
            return
        }
        
        // If not in cache, fetch from Firestore
        let db = Firestore.firestore()
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            guard let data = userDoc.data(),
                  let userName = data["userName"] as? String else {
                await MainActor.run {
                    isLoadingUser = false
                }
                return
            }
            
            let privacy = data["privacy"] as? [String: Any] ?? [:]
            
            let fetchedUser = AppUser(
                id: userId,
                userName: userName,
                firstName: data["firstName"] as? String,
                lastName: data["lastName"] as? String,
                email: data["email"] as? String,
                phoneNumber: data["phone"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                lastUpdated: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                isEmailPublic: privacy["emailSearchable"] as? Bool ?? false,
                isPhonePublic: privacy["phoneSearchable"] as? Bool ?? false,
                isRetiredGeneral: data["isRetiredGeneral"] as? Bool ?? false,
                activeFamilyId: data["activeFamilyId"] as? String,
                friendCount: data["friendCount"] as? Int ?? 0,
                firebaseUID: userId
            )
            
            // Set avatar if available
            if let avatarColorString = data["avatarColor"] as? String,
               let avatarColor = AvatarColor(rawValue: avatarColorString) {
                fetchedUser.avatarColor = avatarColor
            }
            if let avatarTypeString = data["avatarType"] as? String,
               let avatarType = AvatarType(rawValue: avatarTypeString) {
                fetchedUser.avatarType = avatarType
            }
            
            // Cache in SwiftData
            modelContext.insert(fetchedUser)
            try? modelContext.save()
            
            await MainActor.run {
                self.user = fetchedUser
                self.isLoadingUser = false
            }
        } catch {
            print("⚠️ Failed to fetch user \(userId): \(error.localizedDescription)")
            await MainActor.run {
                isLoadingUser = false
            }
        }
    }
    
    private func respondToInvite(accept: Bool) {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                try await friendshipRepository.respondToFriendInvite(inviteId: inviteId, accept: accept)
                
                await MainActor.run {
                    isProcessing = false
                    if accept {
                        hasAccepted = true
                        AnalyticsService.shared.log(.friendRequestAccepted)
                    } else {
                        AnalyticsService.shared.log(.friendRequestDeclined)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showError = true
                    if !accept {
                        // If declining failed, still dismiss
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    FriendInviteDetail(inviteId: "test")
        .environmentObject(FirebaseAuthService())
}

