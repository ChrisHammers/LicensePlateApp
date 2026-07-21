//
//  AddFriendSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel = AddFriendViewModel()

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
                                UserSearchResultRow(result: result, viewModel: viewModel)
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
            }
            .navigationTitle("Add Friend".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
                viewModel.onAppear()
            }
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.onSearchQueryChange()
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
                Text("Friend invitation has been sent successfully.".localized)
            }
            .onDisappear {
                viewModel.cancelSearchTask()
            }
        }
    }
}

struct UserSearchResultRow: View {
    let result: UserRepository.UserSearchResult
    @ObservedObject var viewModel: AddFriendViewModel
    @EnvironmentObject var authService: FirebaseAuthService

    var user: AppUser { result.user }

    var body: some View {
        HStack {
            NavigationLink {
                StandardProfileView(user: user)
            } label: {
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
            .buttonStyle(.plain)

            Button("Add".localized) {
                viewModel.sendInvite(to: result)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Theme.primaryBlue)
            .disabled(viewModel.invitingUserId != nil || !authService.isOnline)
            .accessibleButton(label: "Add Friend".localized)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(user.displayName), @\(user.userName)")
    }
}

#Preview {
    AddFriendSheet()
        .environmentObject(FirebaseAuthService())
}
