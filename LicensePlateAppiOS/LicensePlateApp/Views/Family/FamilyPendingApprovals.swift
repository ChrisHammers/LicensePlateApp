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
                                stamp: viewModel.identityStamp(for: request),
                                expiryLabel: viewModel.expiryLabel(for: request),
                                isExpired: viewModel.isExpired(request),
                                childTargetState: viewModel.childTargetState(for: request),
                                childDraft: viewModel.childDraft(for: request),
                                canApprove: viewModel.canApprove(request: request),
                                expectedAgeOutYearOptions: ExpectedAgeOutYearOptions.options(
                                    currentYear: Calendar.current.component(.year, from: .now)
                                ),
                                isApproveBusy: viewModel.isBusy(requestId: request.requestId, kind: .approve),
                                isDeclineBusy: viewModel.isBusy(requestId: request.requestId, kind: .decline),
                                isDisabled: viewModel.isRowDisabled(requestId: request.requestId),
                                isAwaitingGuardian: request.statusEnum == .awaitingGuardian,
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
                                onCorrectionReasonChange: {
                                    viewModel.setCorrectionReason($0, for: request)
                                },
                                onCorrectionAcknowledgedChange: {
                                    viewModel.setCorrectionAcknowledged($0, for: request)
                                },
                                onCorrectionGuardianAffirmedChange: {
                                    viewModel.setCorrectionGuardianAffirmed($0, for: request)
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
    /// FR-86: identity stamped onto the pending doc at creation (server agent), so two
    /// pending children are distinguishable on this approve screen before — or even
    /// without — a live user-doc resolve. Supplied by the view model from the repository's
    /// parsed projection; `nil` on unstamped rows, which keeps the generic placeholder.
    ///
    /// Device pass 2026-08-17: previously read off the request as a `@Transient`, which is
    /// nil on every row that comes back out of SwiftData — i.e. every row this list renders.
    var stamp: PendingIdentityStamp?
    /// Device pass 2026-08-17: the row's own decision window, rendered from the moment it
    /// appears. Both values are decided by the view model — see `FamilyPendingRequestLifetime`.
    var expiryLabel: String = ""
    var isExpired: Bool = false
    /// COPPA FR-1/FR-25 rendered projections — all decided by the view model.
    let childTargetState: ChildApprovalTargetState
    let childDraft: ChildApprovalDraft
    let canApprove: Bool
    let expectedAgeOutYearOptions: [Int]
    let isApproveBusy: Bool
    let isDeclineBusy: Bool
    let isDisabled: Bool
    /// FR-59.1: the captain approved and the guardian's email confirmation is out.
    /// Nothing here is approvable any more — the outstanding action is in the
    /// guardian's inbox — so the approve controls and the consent acks give way to a
    /// waiting state. Decline stays: it is the cancel.
    var isAwaitingGuardian: Bool = false
    let onIsChildChange: (Bool) -> Void
    let onConsentAcknowledgedChange: (Bool) -> Void
    let onGuardianAffirmedChange: (Bool) -> Void
    let onExpectedAgeOutYearChange: (Int?) -> Void
    /// FR-66(b): the new-guardian correction block, shown only when clearing a KNOWN flag.
    let onCorrectionReasonChange: (ChildStatusCorrectionReason?) -> Void
    let onCorrectionAcknowledgedChange: (Bool) -> Void
    let onCorrectionGuardianAffirmedChange: (Bool) -> Void
    let onApprove: () async -> Bool
    let onDecline: () async -> Bool
    @State private var resolvedUser: AppUser?

    private var displayUser: AppUser? {
        request.user ?? resolvedUser
    }

    private var stampedDisplayName: String? { stamp?.userName }

    private var stampedAvatarId: String? { stamp?.avatarId }

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
                        // Unknown/absent id falls back to the standard placeholder icon
                        // — same catalog lookup roster rows use (AvatarImageView(avatarId:)).
                        AvatarImageView(avatarId: stampedAvatarId, size: 50)
                        Text(stampedDisplayName ?? "User".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                }

                Spacer(minLength: 8)

                if isAwaitingGuardian {
                    awaitingGuardianButtons
                        .layoutPriority(1)
                } else {
                    approvalButtons
                        .layoutPriority(1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pendingApprovalAccessibilityLabel)

            if isAwaitingGuardian {
                awaitingGuardianLine
            } else {
                expiryLine

                childDeclarationSection
            }
        }
        .padding(.vertical, 8)
        .task(id: request.userId) {
            await resolveUserIfNeeded()
        }
    }

    /// FR-59.1 awaiting state: icon + text, never colour alone; the copy names the
    /// outstanding action (the captain-guardian's own inbox).
    private var awaitingGuardianLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 12, weight: .semibold))
                .accessibleDecorative()
            Text("family.approval.awaiting_guardian_subtitle".localized)
                .font(.system(.caption, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.Theme.softBrown)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("family.approval.awaiting_guardian_subtitle".localized)
    }

    private var awaitingGuardianButtons: some View {
        Button {
            Task {
                guard !isDisabled else { return }
                _ = await onDecline()
            }
        } label: {
            InviteActionLabel(
                title: "Cancel".localized,
                isBusy: isDeclineBusy,
                busyKind: .decline
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .accessibleButton(
            label: "family.a11y.cancel_guardian_confirmation".localized,
            hint: "family.approval.awaiting_guardian_subtitle".localized
        )
    }

    /// The decision window. Terminal state carries an icon as well as a colour — state is never
    /// conveyed by colour alone.
    @ViewBuilder
    private var expiryLine: some View {
        if !expiryLabel.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: isExpired ? "clock.badge.xmark" : "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibleDecorative()
                Text(expiryLabel)
                    .font(.system(.caption, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isExpired ? Color.Theme.primaryBlue : Color.Theme.softBrown)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(expiryLabel)
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

            // FR-66(b): clearing a flag we KNOW is set now costs the same evidence as
            // setting one. Mutually exclusive with the consent block above, which is the
            // `isChild == true` branch.
            if ChildApprovalPolicy.showsCorrectionBlock(state: childTargetState, draft: childDraft) {
                FamilyChildCorrectionBlock(
                    draft: childDraft.correction,
                    onReasonChange: onCorrectionReasonChange,
                    onStatusAcknowledgedChange: onCorrectionAcknowledgedChange,
                    onGuardianAffirmedChange: onCorrectionGuardianAffirmedChange
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
        if let name = stampedDisplayName {
            return name
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
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
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
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
}

/// FR-66(b): the state that used to approve with one tap and now cannot.
#Preview("Approval row — clearing a sticky flag") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(requestId: "req-4", familyId: "fam", userId: "u4", requestedBy: "u4", method: .code),
            childTargetState: .alreadyChild,
            childDraft: ChildApprovalDraft(isChild: false),
            canApprove: false,
            expectedAgeOutYearOptions: Array(2026...2039),
            isApproveBusy: false,
            isDeclineBusy: false,
            isDisabled: false,
            onIsChildChange: { _ in },
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in },
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
}

/// FR-86: no cached `AppUser` to resolve (the reinstall / non-readable-child case), so the
/// row renders entirely off the server's stamp instead of "User" + a placeholder avatar.
#Preview("Approval row — stamped identity, no resolved user") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(requestId: "req-5", familyId: "fam", userId: "u5", requestedBy: "u5", method: .code),
            stamp: PendingIdentityStamp(
                firestoreData: ["userName": "pending_pat", "avatarId": "scout_otter"]
            ),
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
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
}

/// Device pass 2026-08-17: the row past its 7-day decision window. Terminal and visibly so —
/// the state the owner previously saw as an ordinary, still-approvable row.
#Preview("Approval row — decision window elapsed") {
    List {
        PendingApprovalRow(
            request: PendingJoinRequest(
                requestId: "req-6",
                familyId: "fam",
                userId: "u6",
                requestedBy: "u6",
                method: .code,
                createdAt: .now.addingTimeInterval(-8 * 24 * 60 * 60)
            ),
            stamp: PendingIdentityStamp(firestoreData: ["userName": "pending_pat"]),
            expiryLabel: "family.pending.expired".localized,
            isExpired: true,
            childTargetState: .notChild,
            childDraft: .initial(for: .notChild),
            canApprove: false,
            expectedAgeOutYearOptions: Array(2026...2039),
            isApproveBusy: false,
            isDeclineBusy: false,
            isDisabled: true,
            onIsChildChange: { _ in },
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in },
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
            onApprove: { false },
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
            onCorrectionReasonChange: { _ in },
            onCorrectionAcknowledgedChange: { _ in },
            onCorrectionGuardianAffirmedChange: { _ in },
            onApprove: { true },
            onDecline: { true }
        )
    }
    .preferredColorScheme(.dark)
}
