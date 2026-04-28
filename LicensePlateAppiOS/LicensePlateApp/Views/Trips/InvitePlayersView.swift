//
//  InvitePlayersView.swift
//  LicensePlateApp
//
//  Step 11.5 — Invite player selection from friends/family only.
//

import SwiftUI

struct InvitePlayersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: InvitePlayersViewModel
    let title: String
    var onDoneSelection: ((Set<String>) -> Void)? = nil

    init(
        viewModel: InvitePlayersViewModel,
        title: String = "Invite Players".localized,
        onDoneSelection: ((Set<String>) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.title = title
        self.onDoneSelection = onDoneSelection
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    } else if viewModel.candidates.isEmpty {
                        Text("No eligible friends or family to invite yet.".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.candidates) { candidate in
                            Button {
                                FeedbackService.shared.buttonTap()
                                viewModel.toggleSelection(userId: candidate.userId)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.displayName)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        Text(candidate.sourceLabel)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                        if candidate.isAlreadyParticipant {
                                            Text("Already a passenger".localized)
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(.green)
                                        } else if candidate.hasPendingInvite {
                                            Text("Invite pending".localized)
                                                .font(.system(.caption2, design: .rounded))
                                                .foregroundStyle(Color.Theme.accentYellow)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: viewModel.selectedUserIds.contains(candidate.userId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.selectedUserIds.contains(candidate.userId) ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!candidate.isSelectable)
                            .opacity(candidate.isSelectable ? 1.0 : 0.65)
                            .listRowBackground(Color.Theme.cardBackground)
                            .accessibilityLabel(candidate.displayName)
                            .accessibilityHint(candidate.isSelectable ? "Double tap to select passenger".localized : "Unavailable for invite".localized)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.mode == .sendInvites ? "Send".localized : "Done".localized) {
                        Task { @MainActor in
                            if viewModel.mode == .sendInvites {
                                let success = await viewModel.sendSelectedInvites()
                                if success {
                                    onDoneSelection?(viewModel.selectedUserIds)
                                    dismiss()
                                }
                            } else {
                                onDoneSelection?(viewModel.selectedUserIds)
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.selectedUserIds.isEmpty || viewModel.isSubmitting)
                }
            }
            .task {
                await viewModel.loadCandidates()
            }
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

#Preview("Invite Players") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return InvitePlayersView(
        viewModel: InvitePlayersViewModel(
            mode: .setupSelection,
            tripSessionId: UUID(),
            tripName: "Preview Trip",
            authService: auth
        )
    )
    .environmentObject(auth)
}
