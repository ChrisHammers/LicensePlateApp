//
//  AddFamilyMemberSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct AddFamilyMemberSheet: View {
    let familyId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: AddFamilyMemberViewModel

    init(familyId: String) {
        self.familyId = familyId
        _viewModel = StateObject(wrappedValue: AddFamilyMemberViewModel(familyId: familyId))
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    Section("Search".localized) {
                        TextField("Username or email".localized, text: $viewModel.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .accessibleTextField(
                                label: "Username or email".localized,
                                hint: "Enter at least 3 characters to search".localized,
                                value: viewModel.searchQuery
                            )
                            .onSubmit {
                                Task { await viewModel.performSearch() }
                            }

                        if viewModel.searchQuery.count < 3 && !viewModel.searchQuery.isEmpty {
                            Text("Enter at least 3 characters to search".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        }

                        if viewModel.isSearching {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Searching...".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                        }
                    }
                    .listRowBackground(Color.Theme.cardBackground)

                    if !viewModel.searchResults.isEmpty {
                        Section("Results".localized) {
                            ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.user.id) { _, result in
                                FamilyMemberSearchResultRow(
                                    result: result,
                                    isInviting: viewModel.isInviting,
                                    onInvite: { viewModel.sendInvite(to: result) }
                                )
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    } else if viewModel.showNoUsersFoundEmptyState {
                        Section {
                            UserSearchEmptyStateView()
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .disabled(viewModel.isInviting)

                if viewModel.isInviting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .navigationTitle("Invite Member".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .disabled(viewModel.isInviting)
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
            }
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.onSearchQueryChange()
            }
            .onDisappear {
                viewModel.cancelSearchTask()
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Invite Sent".localized, isPresented: $viewModel.showSuccessAlert) {
                Button("OK".localized) {
                    dismiss()
                }
            } message: {
                Text("Family invitation has been sent successfully.".localized)
            }
        }
    }
}

struct FamilyMemberSearchResultRow: View {
    let result: UserRepository.UserSearchResult
    let isInviting: Bool
    let onInvite: () -> Void
    @EnvironmentObject var authService: FirebaseAuthService

    var user: AppUser { result.user }

    var body: some View {
        HStack {
            UserDetailNavigationLink(user: user) {
                HStack(spacing: 12) {
                    AvatarImageView(user: user, size: 50)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)

                        Text("@\(user.userName)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)

                        Text("Found by %@".localized(result.matchedField.displayName))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                    }

                    Spacer(minLength: 0)
                }
            }

            Button("Invite".localized) {
                onInvite()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Theme.primaryBlue)
            .disabled(isInviting || !authService.isOnline)
            .accessibleButton(label: "family.a11y.invite_member_button".localized(user.displayName))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(user.displayName), @\(user.userName)")
    }
}

#Preview {
    AddFamilyMemberSheet(familyId: "test")
        .environmentObject(FirebaseAuthService())
}
