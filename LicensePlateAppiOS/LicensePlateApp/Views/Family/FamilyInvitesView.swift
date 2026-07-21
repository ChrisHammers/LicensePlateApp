//
//  FamilyInvitesView.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData
import Combine

struct FamilyInvitesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: FirebaseAuthService
    private let inviteRepository = InviteRepository.shared
    @State private var pendingInvites: [Invite] = []
    @State private var isLoading = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if isLoading {
                    ProgressView()
                } else if pendingInvites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                        
                        Text("No pending invites".localized)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("You don't have any pending family invitations".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(pendingInvites) { invite in
                            FamilyInviteRow(invite: invite)
                                .listRowBackground(Color.Theme.cardBackground)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Family Invites".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                inviteRepository.setModelContext(modelContext)
                loadInvites()
                
                // Start listening for real-time updates
                if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                    inviteRepository.startListening(userId: userId)
                    
                    // Observe repository changes
                    inviteRepository.$invites
                        .sink { allInvites in
                            updateInvites(allInvites)
                        }
                        .store(in: &cancellables)
                }
            }
        }
    }
    
    private func loadInvites() {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        isLoading = true
        
        // Get pending family invites for current user
        let familyInvites = inviteRepository.getFamilyInvites(for: userId)
        pendingInvites = familyInvites.filter { 
            $0.toUserId == userId && $0.statusEnum == .pending 
        }
        
        isLoading = false
    }
    
    private func updateInvites(_ allInvites: [Invite]) {
        guard let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return
        }
        
        let familyInvites = allInvites.filter { $0.typeEnum == .family }
        pendingInvites = familyInvites.filter { 
            $0.toUserId == userId && $0.statusEnum == .pending 
        }
    }
}

struct FamilyInviteRow: View {
    let invite: Invite
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    @State private var showInviteDetail = false
    @State private var family: Family?

    private var rawFamilyName: String? {
        if let name = invite.familyName, !name.isEmpty { return name }
        if let name = family?.name, !name.isEmpty { return name }
        return nil
    }

    private var titleText: String {
        if let name = rawFamilyName {
            return FamilyDisplayFormatting.quotedFamilyTitle(name)
        }
        return "Family Invitation".localized
    }

    private var subtitleText: String {
        if let from = invite.fromUserDisplayName, !from.isEmpty {
            return "From: %@".localized(from)
        }
        return "Tap to view details".localized
    }
    
    var body: some View {
        Button {
            showInviteDetail = true
        } label: {
            HStack(spacing: 12) {
                FamilyInitialAvatarView(
                    familyName: rawFamilyName ?? "?",
                    size: 50
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    if let name = rawFamilyName {
                        (
                            Text("\"\(name)\"")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            + Text(" ")
                            + Text("Family".localized)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.medium)
                        )
                        .foregroundStyle(Color.Theme.primaryBlue)
                    } else {
                        Text(titleText)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    
                    Text(subtitleText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText), \(subtitleText)")
        .sheet(isPresented: $showInviteDetail) {
            if let familyId = invite.familyId {
                FamilyInviteDetail(
                    inviteId: invite.inviteId,
                    familyId: familyId,
                    family: family
                )
                .environmentObject(authService)
            }
        }
        .task {
            await loadFamily()
        }
    }
    
    private func loadFamily() async {
        // Prefer denormalized name; fetch only to pass Family into detail when allowed
        guard invite.familyName == nil || invite.familyName?.isEmpty == true,
              let familyId = invite.familyId else { return }
        
        familyRepository.setModelContext(modelContext)
        
        do {
            if let fetchedFamily = try await familyRepository.fetchFamily(familyId: familyId) {
                await MainActor.run {
                    family = fetchedFamily
                }
            }
        } catch {
            print("❌ Failed to load family: \(error.localizedDescription)")
        }
    }
}

#Preview {
    FamilyInvitesView()
        .environmentObject(FirebaseAuthService())
}

