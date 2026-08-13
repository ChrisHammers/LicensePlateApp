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
                                childTargetState: viewModel.childTargetState(for: request),
                                childDraft: viewModel.childDraft(for: request),
                                canApprove: viewModel.canApprove(request: request),
                                expectedAgeOutYearOptions: ExpectedAgeOutYearOptions.options(
                                    currentYear: Calendar.current.component(.year, from: .now)
                                ),
                                isApproveBusy: viewModel.isBusy(requestId: request.requestId, kind: .approve),
                                isDeclineBusy: viewModel.isBusy(requestId: request.requestId, kind: .decline),
                                isDisabled: viewModel.isRowDisabled(requestId: request.requestId),
                                onIsChildChange: { viewModel.setIsChild($0, for: request) },
                                onConsentAcknowledgedChange: {
                                    viewModel.setConsentAcknowledged($0, for: request)
                                },
                                onGuardianAffirmedChange: {
                                    viewModel.setGuardianAffirmed($0, for: request)
                                },
                                onExpectedAgeOutYearChange: {
                                    viewModel.setExpectedAgeOutYear($0, for: request)
                                },
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
    /// COPPA FR-1/FR-25 rendered projections — all decided by the view model.
    let childTargetState: ChildApprovalTargetState
    let childDraft: ChildApprovalDraft
    let canApprove: Bool
    let expectedAgeOutYearOptions: [Int]
    let isApproveBusy: Bool
    let isDeclineBusy: Bool
    let isDisabled: Bool
    let onIsChildChange: (Bool) -> Void
    let onConsentAcknowledgedChange: (Bool) -> Void
    let onGuardianAffirmedChange: (Bool) -> Void
    let onExpectedAgeOutYearChange: (Int?) -> Void
    let onApprove: () async -> Bool
    let onDecline: () async -> Bool
    @State private var resolvedUser: AppUser?

    private var displayUser: AppUser? {
        request.user ?? resolvedUser
    }

    private var isApproveDisabled: Bool {
        isDisabled || !canApprove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Spacer(minLength: 8)

                approvalButtons
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pendingApprovalAccessibilityLabel)

            childDeclarationSection
        }
        .padding(.vertical, 8)
        .task(id: request.userId) {
            await resolveUserIfNeeded()
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    guard !isApproveDisabled else { return }
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
            .disabled(isApproveDisabled)
            .accessibleButton(
                label: isApproveBusy
                    ? InviteBusyKind.approve.localizedBusyTitle
                    : "family.a11y.approve_join".localized,
                hint: canApprove ? nil : "family.child.approve_blocked_hint".localized
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
    }

    /// FR-1: the child toggle and its consent block. FR-25: when the target is already
    /// flagged — or could not be read at all — the toggle is replaced by a required
    /// yes/no choice, because the server refuses a silent approval.
    @ViewBuilder
    private var childDeclarationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if childTargetState.requiresExplicitDeclaration {
                stickyNotice
                explicitChoicePicker
            } else {
                Toggle(isOn: Binding(
                    get: { childDraft.isChild == true },
                    set: { onIsChildChange($0) }
                )) {
                    Text("family.child.toggle_title".localized)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Color.Theme.primaryBlue)
                .disabled(isDisabled)
                .accessibilityLabel("family.child.toggle_title".localized)
                .accessibilityValue(
                    childDraft.isChild == true
                        ? "family.child.a11y.checked".localized
                        : "family.child.a11y.unchecked".localized
                )
                .accessibilityHint("family.child.toggle_hint".localized)
            }

            if ChildApprovalPolicy.showsConsentBlock(draft: childDraft) {
                FamilyChildConsentBlock(
                    draft: childDraft.consent,
                    yearOptions: expectedAgeOutYearOptions,
                    onConsentAcknowledgedChange: onConsentAcknowledgedChange,
                    onGuardianAffirmedChange: onGuardianAffirmedChange,
                    onExpectedAgeOutYearChange: onExpectedAgeOutYearChange
                )
                .disabled(isDisabled)
            }
        }
    }

    @ViewBuilder
    private var stickyNotice: some View {
        let isSticky = childTargetState == .alreadyChild
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSticky ? "figure.child" : "questionmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibleDecorative()
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    (isSticky
                        ? "family.child.sticky_notice_title"
                        : "family.child.unknown_notice_title").localized
                )
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                Text(
                    (isSticky
                        ? "family.child.sticky_notice_body"
                        : "family.child.unknown_notice_body").localized
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.Theme.primaryBlue.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }

    private var explicitChoicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("family.child.choice_label".localized)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)

            Picker(
                "family.child.choice_label".localized,
                selection: Binding(
                    get: { childDraft.isChild },
                    set: { if let value = $0 { onIsChildChange(value) } }
                )
            ) {
                Text("family.child.choice_is_child".localized).tag(Bool?.some(true))
                Text("family.child.choice_not_child".localized).tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)
            .accessibilityLabel("family.child.choice_label".localized)
            .accessibilityHint("family.child.choice_hint".localized)
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

#Preview("Approval row — adult target") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(requestId: "req-1", familyId: "fam", userId: "u1", requestedBy: "u1", method: .code),
            childTargetState: .notChild,
            childDraft: .initial(for: .notChild),
            canApprove: true,
            expectedAgeOutYearOptions: Array(2026...2039),
            isApproveBusy: false,
            isDeclineBusy: false,
            isDisabled: false,
            onIsChildChange: { _ in },
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
}

#Preview("Approval row — child declared, consent pending") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(requestId: "req-2", familyId: "fam", userId: "u2", requestedBy: "u2", method: .code),
            childTargetState: .notChild,
            childDraft: ChildApprovalDraft(isChild: true),
            canApprove: false,
            expectedAgeOutYearOptions: Array(2026...2039),
            isApproveBusy: false,
            isDeclineBusy: false,
            isDisabled: false,
            onIsChildChange: { _ in },
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
}

#Preview("Approval row — sticky child target") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(requestId: "req-3", familyId: "fam", userId: "u3", requestedBy: "u3", method: .code),
            childTargetState: .alreadyChild,
            childDraft: .initial(for: .alreadyChild),
            canApprove: false,
            expectedAgeOutYearOptions: Array(2026...2039),
            isApproveBusy: false,
            isDeclineBusy: false,
            isDisabled: false,
            onIsChildChange: { _ in },
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
    .preferredColorScheme(.dark)
}
