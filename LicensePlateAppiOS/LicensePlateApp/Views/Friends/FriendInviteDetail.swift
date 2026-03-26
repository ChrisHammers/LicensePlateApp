//
//  FriendInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FriendInviteDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FriendInviteDetailViewModel

    init(inviteId: String) {
        _viewModel = StateObject(wrappedValue: FriendInviteDetailViewModel(inviteId: inviteId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    if viewModel.isLoadingUser {
                        ProgressView()
                            .padding()
                            .accessibilityLabel("Loading".localized)
                    } else if let user = viewModel.user {
                        UserImageView(user: user, size: 100)

                        Text(user.displayName)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)

                        Text("@\(user.userName)")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    } else {
                        Text("Friend Request".localized)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }

                    if viewModel.hasAccepted {
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
                        .accessibilityLabel("Done".localized)
                    } else {
                        Button {
                            viewModel.respondToInvite(accept: true, onDeclineDismiss: { dismiss() })
                        } label: {
                            Text("Accept".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.isProcessing || !authService.isOnline)
                        .accessibilityLabel("Accept friend request".localized)

                        Button {
                            viewModel.respondToInvite(accept: false, onDeclineDismiss: { dismiss() })
                        } label: {
                            Text("Decline".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.isProcessing || !authService.isOnline)
                        .accessibilityLabel("Decline friend request".localized)
                    }

                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding()
            }
            .navigationTitle("Friend Invite".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .task {
                viewModel.configure(authService: authService, modelContext: modelContext)
                await viewModel.loadInviteAndUser()
            }
        }
    }
}

#Preview {
    FriendInviteDetail(inviteId: "test")
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Invite.self], inMemory: true)
}
