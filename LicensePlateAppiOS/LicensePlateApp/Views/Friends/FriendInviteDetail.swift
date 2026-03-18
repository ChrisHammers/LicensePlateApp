//
//  FriendInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

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
                InviteRepository.shared.setModelContext(modelContext)
            }
            .task {
                await loadInviteAndUser()
            }
        }
    }
    
    private func loadInviteAndUser() async {
        isLoadingUser = true
        
        let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        
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
        } else if let currentUserId = currentUserId {
            await InviteRepository.shared.refreshInvite(inviteId: inviteId, userId: currentUserId)
            fromUserId = InviteRepository.shared.getInvite(inviteId: inviteId, userId: currentUserId)?.fromUserId
        }
        
        guard let userId = fromUserId else {
            await MainActor.run {
                isLoadingUser = false
            }
            return
        }
        
        do {
            if let fetchedUser = try await UserRepository.shared.getUser(userId: userId) {
                await MainActor.run {
                    self.user = fetchedUser
                    self.isLoadingUser = false
                }
                return
            }
        } catch {
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
        }
        
        await MainActor.run {
            isLoadingUser = false
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
                
                // Refresh the invite to get the latest status from Firestore
                if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                    await InviteRepository.shared.refreshInvite(inviteId: inviteId, userId: userId)
                }
                
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

