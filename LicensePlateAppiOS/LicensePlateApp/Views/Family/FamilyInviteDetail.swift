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
    @StateObject private var viewModel: FamilyInviteDetailViewModel

    init(inviteId: String, familyId: String, family: Family?) {
        self.inviteId = inviteId
        self.familyId = familyId
        self.family = family
        _viewModel = StateObject(wrappedValue: FamilyInviteDetailViewModel(inviteId: inviteId, familyId: familyId))
    }

    private var displayFamilyName: String? {
        if let name = family?.name, !name.isEmpty { return name }
        if let name = viewModel.invite?.familyName, !name.isEmpty { return name }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                ScrollView {
                    VStack(spacing: 24) {
                        familyHeaderSection
                        inviterSection
                        
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
                            .accessibleButton(label: "family.a11y.accept_invite".localized)
                            
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
                            .accessibleButton(label: "family.a11y.decline_invite".localized)
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
            .task {
                viewModel.configure(authService: authService, modelContext: modelContext)
                await viewModel.loadInviteAndInviter()
            }
        }
    }

    @ViewBuilder
    private var familyHeaderSection: some View {
        if viewModel.isLoadingInviter && displayFamilyName == nil {
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
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.Theme.cardBackground)
            .cornerRadius(16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(FamilyDisplayFormatting.invitedToJoinSentence(name))
        } else {
            Text("Family Invitation".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
        }
    }

    @ViewBuilder
    private var inviterSection: some View {
        if viewModel.isLoadingInviter && viewModel.inviter == nil {
            ProgressView()
                .accessibilityLabel("Loading".localized)
        } else if let inviter = viewModel.inviter {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    UserDetailNavigationLink(user: inviter) {
                        UserIdentityRowView(
                            user: inviter,
                            subtitle: nil,
                            avatarSize: 40
                        )
                    }

                    Text("Captain".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(8)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(inviter.displayName), @\(inviter.userName), \("Captain".localized)")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Theme.cardBackground)
            .cornerRadius(16)
        }
    }
}

#Preview {
    FamilyInviteDetail(inviteId: "test", familyId: "test", family: nil)
        .environmentObject(FirebaseAuthService())
}
