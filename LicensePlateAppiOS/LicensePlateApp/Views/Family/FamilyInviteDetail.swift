//
//  FamilyInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilyInviteDetail: View {
    let inviteId: String
    let familyId: String
    let family: Family? // Optional - passed from parent if available
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    private let inviteRepository = InviteRepository.shared
    @StateObject private var viewModel: FamilyInviteDetailViewModel
    @State private var loadedFamily: Family?
    @State private var loadedInvite: Invite?
    @State private var captains: [FamilyMember] = []
    @State private var isLoadingFamily = false
    /// Resolved avatar ids for snapshot captains (from stamp or user fetch).
    @State private var captainAvatarByKey: [String: String] = [:]

    init(inviteId: String, familyId: String, family: Family?) {
        self.inviteId = inviteId
        self.familyId = familyId
        self.family = family
        _viewModel = StateObject(wrappedValue: FamilyInviteDetailViewModel(inviteId: inviteId, familyId: familyId))
    }
    
    private var displayFamily: Family? {
        family ?? loadedFamily
    }

    private var displayFamilyName: String? {
        if let name = displayFamily?.name, !name.isEmpty { return name }
        if let name = loadedInvite?.familyName, !name.isEmpty { return name }
        return nil
    }

    private var snapshotCaptains: [FamilyInviteCaptainPreview] {
        loadedInvite?.captainsPreview ?? []
    }

    /// Prefer denormalized snapshot for invitees (members fetch is usually denied).
    private var showSnapshotCaptains: Bool {
        !snapshotCaptains.isEmpty
    }

    private var showLiveCaptains: Bool {
        !showSnapshotCaptains && !captains.isEmpty
    }

    private func resolvedAvatarId(for captain: FamilyInviteCaptainPreview) -> String? {
        if let keyed = captainAvatarByKey[captain.id], !keyed.isEmpty {
            return keyed
        }
        if let userId = captain.userId, let keyed = captainAvatarByKey[userId], !keyed.isEmpty {
            return keyed
        }
        if let stamped = captain.avatarId, !stamped.isEmpty {
            return stamped
        }
        if captain.isCreator, let creatorAvatar = loadedInvite?.creatorAvatarId, !creatorAvatar.isEmpty {
            return creatorAvatar
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                ScrollView {
                    VStack(spacing: 24) {
                        familyHeaderSection

                        if showLiveCaptains {
                            liveCaptainsSection
                        } else if showSnapshotCaptains {
                            snapshotCaptainsSection
                        }
                        
                        if viewModel.hasAccepted {
                            VStack(spacing: 12) {
                                Text("Waiting for Captain approval".localized)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                
                                Text("A family captain will review your request".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                            }
                            .padding()
                        } else {
                            Button {
                                viewModel.respondToInvite(accept: true, onDeclineDismiss: { })
                            } label: {
                                Text("Accept".localized)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.Theme.primaryBlue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(viewModel.isProcessing || !authService.isOnline)
                            .accessibilityLabel("Accept".localized)
                            
                            Button {
                                viewModel.respondToInvite(accept: false, onDeclineDismiss: { dismiss() })
                            } label: {
                                Text("Decline".localized)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.Theme.cardBackground)
                                    .foregroundColor(Color.Theme.primaryBlue)
                                    .cornerRadius(12)
                            }
                            .disabled(viewModel.isProcessing || !authService.isOnline)
                            .accessibilityLabel("Decline".localized)
                        }
                    
                        if !authService.isOnline {
                            Text("Requires network connection".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                    
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red)
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Family Invite".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                inviteRepository.setModelContext(modelContext)
                viewModel.configure(authService: authService, modelContext: modelContext)
                hydrateInviteSnapshot()
                Task { await enrichCaptainAvatars() }
                loadFamilyData()
            }
        }
    }

    @ViewBuilder
    private var familyHeaderSection: some View {
        if isLoadingFamily && displayFamilyName == nil {
            ProgressView()
                .padding()
                .accessibilityLabel("Loading".localized)
        } else if let name = displayFamilyName {
            VStack(spacing: 16) {
                FamilyInitialAvatarView(familyName: name, size: 72)

                Text(FamilyDisplayFormatting.invitedToJoinSentence(name))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .multilineTextAlignment(.center)

                if let inviter = loadedInvite?.fromUserDisplayName, !inviter.isEmpty {
                    Text("From: %@".localized(inviter))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.Theme.cardBackground)
            .cornerRadius(16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel(familyName: name))
        } else {
            Text("Family Invitation".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
        }
    }

    @ViewBuilder
    private var liveCaptainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captains".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            
            ForEach(captains) { captain in
                HStack {
                    if let user = captain.user {
                        UserIdentityRowView(
                            user: user,
                            subtitle: nil,
                            avatarSize: 40
                        )
                    } else {
                        UserIdentityRowView(
                            avatarId: captainAvatarByKey[captain.userId],
                            displayName: "Captain".localized,
                            subtitle: nil,
                            avatarSize: 40
                        )
                    }
                    
                    Text(captain.roleEnum == .creator ? "Creator".localized : "Captain".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(8)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(captainAccessibilityLabel(captain))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.cardBackground)
        .cornerRadius(16)
    }

    @ViewBuilder
    private var snapshotCaptainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captains".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            
            ForEach(snapshotCaptains) { captain in
                HStack {
                    UserIdentityRowView(
                        avatarId: resolvedAvatarId(for: captain),
                        displayName: captain.displayName,
                        subtitle: captain.userName.isEmpty ? nil : "@\(captain.userName)",
                        avatarSize: 40
                    )
                    
                    Text(captain.isCreator ? "Creator".localized : "Captain".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(8)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(snapshotCaptainAccessibilityLabel(captain))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.cardBackground)
        .cornerRadius(16)
    }

    private func hydrateInviteSnapshot() {
        if let cached = inviteRepository.getInvite(inviteId: inviteId) {
            loadedInvite = cached
        }
        // Also try with current user filter if available
        if loadedInvite == nil,
           let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
            loadedInvite = inviteRepository.getInvite(inviteId: inviteId, userId: userId)
        }
    }
    
    private func loadFamilyData() {
        if family == nil && displayFamilyName == nil {
            isLoadingFamily = true
        }
        
        Task {
            // Refresh invite from Firestore so deep-link / push paths get the snapshot
            if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                await inviteRepository.refreshInvite(inviteId: inviteId, userId: userId)
                await MainActor.run {
                    loadedInvite = inviteRepository.getInvite(inviteId: inviteId)
                        ?? inviteRepository.getInvite(inviteId: inviteId, userId: userId)
                }
                await enrichCaptainAvatars()
            }

            do {
                var fetchedFamily: Family?
                if family == nil {
                    fetchedFamily = try await familyRepository.fetchFamily(familyId: familyId)
                }
                
                let fetchedMembers = try await familyRepository.fetchMembers(familyId: familyId)
                
                let linkedMembers = familyRepository.getMembers(familyId: familyId)
                let sourceMembers = linkedMembers.isEmpty ? fetchedMembers : linkedMembers
                
                let captainsList = sourceMembers.filter { member in
                    member.roleEnum == .captain || member.roleEnum == .creator
                }
                
                await MainActor.run {
                    if let fetchedFamily = fetchedFamily {
                        loadedFamily = fetchedFamily
                    }
                    captains = captainsList
                    isLoadingFamily = false
                }
                await enrichCaptainAvatars()
            } catch {
                await MainActor.run {
                    isLoadingFamily = false
                    print("❌ Failed to load family data: \(error.localizedDescription)")
                }
                await enrichCaptainAvatars()
            }
        }
    }

    private func enrichCaptainAvatars() async {
        let captains = loadedInvite?.captainsPreview ?? []
        UserRepository.shared.setModelContext(modelContext)
        var resolved: [String: String] = [:]

        func store(key: String, avatarId: String?) {
            guard let avatarId, !avatarId.isEmpty else { return }
            resolved[key] = avatarId
        }

        if let creatorAvatar = loadedInvite?.creatorAvatarId {
            store(key: "creator", avatarId: creatorAvatar)
        }
        if let fromAvatar = loadedInvite?.fromUserAvatarId {
            store(key: "from", avatarId: fromAvatar)
        }

        // Seed from stamped snapshot values first
        for captain in captains {
            store(key: captain.id, avatarId: captain.avatarId)
            if let userId = captain.userId {
                store(key: userId, avatarId: captain.avatarId)
            }
            if captain.isCreator, let creatorAvatar = loadedInvite?.creatorAvatarId {
                store(key: captain.id, avatarId: creatorAvatar)
            }
        }

        // Resolve via public user profiles (same path as friend invite detail)
        var userIds = Set(captains.compactMap(\.userId).filter { !$0.isEmpty })
        if let fromUserId = loadedInvite?.fromUserId, !fromUserId.isEmpty {
            userIds.insert(fromUserId)
        }
        for member in self.captains {
            userIds.insert(member.userId)
        }

        for userId in userIds {
            if let user = try? await UserRepository.shared.getUser(userId: userId),
               let avatarId = user.avatarId,
               !avatarId.isEmpty {
                store(key: userId, avatarId: avatarId)
                if let captain = captains.first(where: { $0.userId == userId }) {
                    store(key: captain.id, avatarId: avatarId)
                }
            }
        }

        await MainActor.run {
            captainAvatarByKey = resolved
        }
    }

    private func headerAccessibilityLabel(familyName: String) -> String {
        var parts = [FamilyDisplayFormatting.invitedToJoinSentence(familyName)]
        if let inviter = loadedInvite?.fromUserDisplayName, !inviter.isEmpty {
            parts.append("From: %@".localized(inviter))
        }
        return parts.joined(separator: ", ")
    }

    private func captainAccessibilityLabel(_ captain: FamilyMember) -> String {
        let role = captain.roleEnum == .creator ? "Creator".localized : "Captain".localized
        if let user = captain.user {
            return "\(user.displayName), @\(user.userName), \(role)"
        }
        return "\("Captain".localized), \(role)"
    }

    private func snapshotCaptainAccessibilityLabel(_ captain: FamilyInviteCaptainPreview) -> String {
        let role = captain.isCreator ? "Creator".localized : "Captain".localized
        if captain.userName.isEmpty {
            return "\(captain.displayName), \(role)"
        }
        return "\(captain.displayName), @\(captain.userName), \(role)"
    }
    
}

#Preview {
    FamilyInviteDetail(inviteId: "test", familyId: "test", family: nil)
        .environmentObject(FirebaseAuthService())
}
