//
//  FamilyPendingApprovals.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilyPendingApprovals: View {
    let familyId: String
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FamilyPendingApprovalsViewModel

    init(familyId: String) {
        self.familyId = familyId
        _viewModel = StateObject(wrappedValue: FamilyPendingApprovalsViewModel(familyId: familyId))
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if viewModel.pendingRequests.isEmpty {
                        Text("No pending requests".localized)
                            .foregroundStyle(Color.Theme.softBrown)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .listRowBackground(Color.Theme.cardBackground)
                    } else {
                        ForEach(viewModel.pendingRequests) { request in
                            PendingApprovalRow(
                                request: request,
                                isApproveBusy: viewModel.isBusy(requestId: request.requestId, kind: .approve),
                                isDeclineBusy: viewModel.isBusy(requestId: request.requestId, kind: .decline),
                                isDisabled: viewModel.isRowDisabled(requestId: request.requestId),
                                onApprove: {
                                    await viewModel.approve(request: request)
                                },
                                onDecline: {
                                    await viewModel.decline(request: request)
                                }
                            )
                            .listRowBackground(Color.Theme.cardBackground)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Pending Approvals".localized)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
                viewModel.onAppear()
            }
            .task(id: familyId) {
                viewModel.configure(authService: authService, modelContext: modelContext)
                await viewModel.refreshPendingRequests()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .refreshable {
                await viewModel.refreshPendingRequests()
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error".localized)
            }
        }
    }
}

struct PendingApprovalRow: View {
    let request: PendingJoinRequest
    let isApproveBusy: Bool
    let isDeclineBusy: Bool
    let isDisabled: Bool
    let onApprove: () async -> Bool
    let onDecline: () async -> Bool
    @State private var resolvedUser: AppUser?

    private var displayUser: AppUser? {
        request.user ?? resolvedUser
    }

    var body: some View {
        HStack {
            if let user = displayUser {
                UserIdentityRowView(user: user, subtitle: nil, avatarSize: 50)
            } else {
                HStack(spacing: 12) {
                    AvatarImageView(avatarId: nil, size: 50)
                    Text("User".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        guard !isDisabled else { return }
                        _ = await onApprove()
                    }
                } label: {
                    InviteActionLabel(
                        title: "Approve".localized,
                        isBusy: isApproveBusy,
                        busyKind: .approve
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Theme.primaryBlue)
                .disabled(isDisabled)
                .accessibleButton(
                    label: isApproveBusy
                        ? InviteBusyKind.approve.localizedBusyTitle
                        : "family.a11y.approve_join".localized
                )

                Button {
                    Task {
                        guard !isDisabled else { return }
                        _ = await onDecline()
                    }
                } label: {
                    InviteActionLabel(
                        title: "Decline".localized,
                        isBusy: isDeclineBusy,
                        busyKind: .decline
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .disabled(isDisabled)
                .accessibleButton(
                    label: isDeclineBusy
                        ? InviteBusyKind.decline.localizedBusyTitle
                        : "family.a11y.decline_join".localized
                )
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pendingApprovalAccessibilityLabel)
        .task(id: request.userId) {
            await resolveUserIfNeeded()
        }
    }

    private var pendingApprovalAccessibilityLabel: String {
        if let user = displayUser {
            return "\(user.displayName), @\(user.userName)"
        }
        return "User".localized
    }

    private func resolveUserIfNeeded() async {
        if request.user != nil {
            await MainActor.run { resolvedUser = nil }
            return
        }
        do {
            if let fetched = try await UserRepository.shared.getUser(userId: request.userId) {
                await MainActor.run {
                    self.resolvedUser = fetched
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ PendingApprovalRow failed to resolve user \(request.userId): \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    FamilyPendingApprovals(familyId: "test")
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [PendingJoinRequest.self], inMemory: true)
}
