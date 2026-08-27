//
//  FamilySettings.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilySettings: View {
    let familyId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FamilySettingsViewModel
    @State private var showLeaveFamilyConfirmation = false
    @State private var showDeleteFamilyConfirmation = false
    
    init(familyId: String) {
        self.familyId = familyId
        let familyRepo = FamilyRepository.shared
        _viewModel = StateObject(wrappedValue: FamilySettingsViewModel(
            familyRepository: familyRepo,
            authService: FirebaseAuthService()
        ))
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    // Family Name
                    if viewModel.isCaptainOrCreator {
                        Section("Family Name".localized) {
                            HStack(spacing: 12) {
                                FamilyInitialAvatarView(
                                    familyName: viewModel.familyName.isEmpty ? "?" : viewModel.familyName,
                                    size: 44
                                )
                                .accessibilityHidden(true)
                                SettingEditableTextRow(
                                    title: "Name".localized,
                                    value: $viewModel.familyName,
                                    placeholder: "Enter family name".localized,
                                    detail: nil,
                                    isDisabled: viewModel.isSavingName || !authService.isOnline,
                                    onSave: {
                                        viewModel.saveFamilyName()
                                    },
                                    onCancel: {
                                        viewModel.cancelFamilyNameEditing()
                                    }
                                )
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                        
                        // Members
                        Section("Members".localized) {
                            ForEach(viewModel.members) { member in
                                FamilyMemberSettingsRow(
                                    member: member,
                                    familyCreatorId: viewModel.family?.creatorId,
                                    isChild: viewModel.isChildMember(memberId: member.userId)
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if viewModel.canRemove(memberId: member.userId) {
                                        Button(role: .destructive) {
                                            viewModel.confirmRemoveMember(memberId: member.userId)
                                        } label: {
                                            Label("Remove".localized, systemImage: "person.fill.xmark")
                                        }
                                        .disabled(viewModel.isRemovingMember)
                                    }
                                }

                                // COPPA F-8 (FR-2/5/20/29/30): creator/captain-only child
                                // controls. Mirrors the server's target rules — no self,
                                // no creator — so a control is never offered that the
                                // callable would reject.
                                if viewModel.canManageChildStatus(memberId: member.userId) {
                                    FamilyChildManageControls(
                                        target: viewModel.childMemberTarget(for: member),
                                        isChild: viewModel.isChildMember(memberId: member.userId),
                                        // Fix 2 (2026-08-16): every row disables while ANY
                                        // deletion is in flight, but only the matching row
                                        // spins — see `isDeletingChildData(memberId:)`.
                                        isBusy: viewModel.isSavingChildStatus || viewModel.isChildDataDeletionInFlight,
                                        isDeletingChildData: viewModel.isDeletingChildData(memberId: member.userId),
                                        onMarkAsChild: { viewModel.beginMarkAsChild($0) },
                                        onCorrect: { viewModel.beginCorrectChildStatus($0) },
                                        onOpenPrivacy: { viewModel.openChildPrivacy($0) },
                                        onRemoveAndDelete: { viewModel.beginRemoveAndDeleteChildData($0) }
                                    )
                                }
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)

                    }

                    
                    // Leave Family (All members except creator)
                    if !viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showLeaveFamilyConfirmation = true
                            } label: {
                                if viewModel.isLeavingFamily {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Leaving...".localized)
                                    }
                                } else {
                                    Text("Leave Family".localized)
                                        .foregroundColor(.red)
                                }
                            }
                            .disabled(viewModel.isLeavingFamily)
                            .accessibleButton(label: "Leave Family".localized)
                        } header: {
                            Text("Leave Family".localized)
                        } footer: {
                            Text("You will be removed from this family and will need to be invited again to rejoin.".localized)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                    
                    // Danger Zone (Creator only)
                    if viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showDeleteFamilyConfirmation = true
                            } label: {
                                if viewModel.isDeletingFamily {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Deleting...".localized)
                                    }
                                } else {
                                    Text("Delete Family".localized)
                                }
                            }
                            .foregroundColor(.red)
                            .disabled(viewModel.isDeletingFamily)
                            .accessibleButton(
                                label: viewModel.isDeletingFamily
                                    ? "Deleting...".localized
                                    : "Delete Family".localized
                            )
                        } header: {
                            Text("Danger Zone".localized)
                        } footer: {
                            Text("This will permanently delete the family and remove all members. This action cannot be undone.".localized)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Family Settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.setAuthService(authService)
                viewModel.loadData(familyId: familyId)
                // Owner (2026-08-16): roster hydration only fetches a member's user doc
                // once per session and caches it — this forces a fresh read so avatar/
                // username edits made elsewhere stop being stuck on the old copy.
                viewModel.refreshMemberIdentitiesIfNeeded()
            }
            .onChange(of: viewModel.didLeaveOrDelete) { _, didLeave in
                if didLeave { dismiss() }
            }
            .alert("Leave Family".localized, isPresented: $showLeaveFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Leave".localized, role: .destructive) {
                    viewModel.leaveFamily()
                }
            } message: {
                Text("Are you sure you want to leave this family? You will need to be invited again to rejoin.".localized)
            }
            .alert(
                "Remove Family Member".localized,
                isPresented: Binding(
                    get: { viewModel.memberIdPendingRemoval != nil },
                    set: { if !$0 { viewModel.cancelRemoveMember() } }
                )
            ) {
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelRemoveMember()
                }
                Button("Remove".localized, role: .destructive) {
                    viewModel.removePendingMember()
                }
            } message: {
                Text("They will be removed from this family and must be invited again to rejoin.".localized)
            }
            .alert("Error".localized, isPresented: $viewModel.showErrorAlert) {
                Button("OK".localized) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .alert("Delete Family".localized, isPresented: $showDeleteFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Delete".localized, role: .destructive) {
                    viewModel.deleteFamily()
                }
            } message: {
                Text("Are you sure you want to delete this family? This will permanently remove the family and all its members. This action cannot be undone.".localized)
            }
            .modifier(FamilyChildManagementPresentations(viewModel: viewModel))
        }
    }
}

/// COPPA F-8 presentation layer, split out so `FamilySettings.body` stays inside the
/// type checker's budget. Sheets present through `item:` (identity preserved per member)
/// and both destructive paths keep their own confirmation step.
private struct FamilyChildManagementPresentations: ViewModifier {
    @ObservedObject var viewModel: FamilySettingsViewModel

    func body(content: Content) -> some View {
        content
            // FR-2 set-true: consent capture before the callable is ever sent.
            .sheet(item: $viewModel.childConsentTarget) { target in
                FamilyChildConsentSheet(target: target, viewModel: viewModel)
            }
            // FR-29: read-only review.
            .sheet(item: $viewModel.childPrivacyTarget) { target in
                FamilyChildPrivacyView(
                    target: target,
                    isChild: viewModel.isChildMember(memberId: target.memberUserId),
                    loadConsentHistory: { childUserId in
                        try await viewModel.loadConsentHistory(childUserId: childUserId)
                    }
                )
            }
            // FR-5: corrections only — the two enumerated reasons, with the
            // participation-ending paths signposted separately in the message.
            .confirmationDialog(
                "family.child.correction_dialog_title".localized,
                isPresented: Binding(
                    get: { viewModel.childCorrectionTarget != nil },
                    set: { if !$0 { viewModel.cancelCorrectChildStatus() } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(ChildStatusCorrectionReason.allCases) { reason in
                    Button(reason.localizedTitle) {
                        viewModel.applyCorrection(reason: reason)
                    }
                }
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelCorrectChildStatus()
                }
            } message: {
                Text("family.child.correction_dialog_message".localized)
            }
            // FR-30 step 1 of 2. The dismissal callback must NOT be the full cancel:
            // SwiftUI fires it after the "Continue" action too, which would clear the
            // just-armed final target and step 2 would never present.
            .alert(
                "family.child.remove_delete_title".localized,
                isPresented: Binding(
                    get: { viewModel.childDeletionTarget != nil },
                    set: { if !$0 { viewModel.dismissInitialDeletionConfirmation() } }
                )
            ) {
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelChildDataDeletion()
                }
                Button("Continue".localized, role: .destructive) {
                    viewModel.advanceToFinalDeletionConfirmation()
                }
            } message: {
                Text("family.child.remove_delete_message".localized)
            }
            // FR-30 step 2 of 2 — the irreversible one.
            .alert(
                "family.child.remove_delete_final_title".localized,
                isPresented: Binding(
                    get: { viewModel.childDeletionFinalTarget != nil },
                    set: { if !$0 { viewModel.cancelChildDataDeletion() } }
                )
            ) {
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelChildDataDeletion()
                }
                Button("family.child.remove_delete_confirm".localized, role: .destructive) {
                    viewModel.confirmChildDataDeletion()
                }
            } message: {
                Text("family.child.remove_delete_final_message".localized)
            }
    }
}

/// Per-member manage controls (creator/captain only). Rendered inline under the member
/// row so the action and its subject are never ambiguous.
struct FamilyChildManageControls: View {
    let target: FamilyChildMemberTarget
    let isChild: Bool
    let isBusy: Bool
    /// F-8 device testing (2026-08-15): the FR-30 deletion specifically, so its control
    /// can show its own progress feedback instead of just going silently unresponsive
    /// for however long the callable takes (`isBusy` already disables every control
    /// in this stack; this additionally drives the spinner on the one causing it).
    var isDeletingChildData: Bool = false
    let onMarkAsChild: (FamilyChildMemberTarget) -> Void
    let onCorrect: (FamilyChildMemberTarget) -> Void
    let onOpenPrivacy: (FamilyChildMemberTarget) -> Void
    let onRemoveAndDelete: (FamilyChildMemberTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isChild {
                controlButton(
                    title: "family.child.manage_privacy".localized,
                    systemImage: "lock.shield",
                    hint: "family.child.manage_privacy_hint".localized
                ) {
                    onOpenPrivacy(target)
                }
                controlButton(
                    title: "family.child.manage_clear".localized,
                    systemImage: "pencil.and.outline",
                    hint: "family.child.manage_clear_hint".localized
                ) {
                    onCorrect(target)
                }
                controlButton(
                    title: "family.child.manage_remove_delete".localized,
                    systemImage: "trash",
                    hint: "family.child.manage_remove_delete_hint".localized,
                    isDestructive: true,
                    isBusy: isDeletingChildData,
                    busyTitle: "Deleting...".localized
                ) {
                    onRemoveAndDelete(target)
                }
            } else {
                controlButton(
                    title: "family.child.manage_mark".localized,
                    systemImage: "figure.child",
                    hint: "family.child.manage_mark_hint".localized
                ) {
                    onMarkAsChild(target)
                }
            }
        }
        .padding(.leading, 52)
        .padding(.bottom, 4)
        .disabled(isBusy)
    }

    private func controlButton(
        title: String,
        systemImage: String,
        hint: String,
        isDestructive: Bool = false,
        isBusy: Bool = false,
        busyTitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(busyTitle ?? title)
                        .font(.system(.footnote, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                        .accessibleDecorative()
                    Text(title)
                        .font(.system(.footnote, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? Color.red : Color.Theme.primaryBlue)
            .frame(minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibleButton(
            label: "\(isBusy ? (busyTitle ?? title) : title), \(target.displayName)",
            hint: hint
        )
    }
}

/// FR-2 set-true consent sheet. The same `FamilyChildConsentBlock` the approval flow
/// uses, so the affirmation wording can never fork.
private struct FamilyChildConsentSheet: View {
    let target: FamilyChildMemberTarget
    @ObservedObject var viewModel: FamilySettingsViewModel

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    Section {
                        Text("family.child.set_sheet_subject".localized(target.displayName))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.Theme.cardBackground)

                    Section {
                        FamilyChildConsentBlock(
                            draft: viewModel.childConsentDraft,
                            yearOptions: viewModel.expectedAgeOutYearOptions,
                            onConsentAcknowledgedChange: { viewModel.setChildConsentAcknowledged($0) },
                            onGuardianAffirmedChange: { viewModel.setChildGuardianAffirmed($0) },
                            onExpectedAgeOutYearMonthChange: { viewModel.setChildExpectedAgeOutYearMonth($0) }
                        )
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("family.child.set_sheet_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { viewModel.cancelMarkAsChild() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("family.child.set_confirm".localized) {
                        viewModel.confirmMarkAsChild()
                    }
                    .disabled(!viewModel.canConfirmMarkAsChild || viewModel.isSavingChildStatus)
                    .accessibleButton(
                        label: "family.child.set_confirm".localized,
                        hint: viewModel.canConfirmMarkAsChild
                            ? nil
                            : "family.child.approve_blocked_hint".localized
                    )
                }
            }
        }
    }
}

struct FamilyMemberSettingsRow: View {
    let member: FamilyMember
    let familyCreatorId: String?
    /// COPPA FR-20 projection (`families/{id}/members/{uid}.isChild`), passed in by the
    /// view model. The row never derives it.
    var isChild: Bool = false
    @EnvironmentObject private var authService: FirebaseAuthService

    private var rolePresentation: FamilyMemberRolePresentation {
        FamilyMemberRolePresentation.make(
            role: member.roleEnum,
            memberUserId: member.userId,
            familyCreatorId: familyCreatorId
        )
    }

    private var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    private var isSelfMember: Bool {
        guard let user = member.user else {
            return member.userId == currentUserId
        }
        return UserDetailNavigation.isSelfProfile(user: user, currentUserId: currentUserId)
    }

    private func decoratedMemberName(for user: AppUser?) -> String {
        let raw = user?.displayName ?? "Member".localized
        guard user != nil else { return raw }
        return ParticipantDisplayName.decorated(raw, isCurrentUser: isSelfMember)
    }

    var body: some View {
        if let user = member.user {
            UserDetailNavigationLink(
                user: user,
                isSelfProfile: isSelfMember
            ) {
                settingsRowContent(user: user)
            }
            .padding(.vertical, 8)
            .accessibilityLabel(settingsMemberAccessibilityLabel)
        } else {
            settingsRowContent(user: nil)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(settingsMemberAccessibilityLabel)
        }
    }

    private func settingsRowContent(user: AppUser?) -> some View {
        HStack {
            if let user {
                AvatarImageView(user: user, size: 40)
            } else {
                AvatarImageView(avatarId: nil, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(decoratedMemberName(for: user))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                if let userName = user?.userName {
                    Text("@\(userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }

                Text(rolePresentation.roleText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }

            Spacer()

            if isChild {
                FamilyChildBadge()
            }

            if rolePresentation.showsCreatorBadge {
                FamilyCreatorBadge()
            }
        }
    }

    private var settingsMemberAccessibilityLabel: String {
        // FR-22: child status reaches VoiceOver as text, never as a color-only cue.
        let childSuffix = isChild ? ", \("family.child.a11y.badge".localized)" : ""
        if let user = member.user {
            return "\(decoratedMemberName(for: user)), @\(user.userName), \(rolePresentation.accessibilityText)\(childSuffix)"
        }
        return "\("Member".localized), \(rolePresentation.accessibilityText)\(childSuffix)"
    }
}

#Preview("Family settings — creator") {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

#Preview("Family settings — member") {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

#Preview("Child manage controls — flagged child") {
    List {
        FamilyChildManageControls(
            target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
            isChild: true,
            isBusy: false,
            onMarkAsChild: { _ in },
            onCorrect: { _ in },
            onOpenPrivacy: { _ in },
            onRemoveAndDelete: { _ in }
        )
    }
}

#Preview("Child manage controls — deleting data") {
    List {
        FamilyChildManageControls(
            target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
            isChild: true,
            isBusy: true,
            isDeletingChildData: true,
            onMarkAsChild: { _ in },
            onCorrect: { _ in },
            onOpenPrivacy: { _ in },
            onRemoveAndDelete: { _ in }
        )
    }
}

#Preview("Child manage controls — not a child, dark") {
    List {
        FamilyChildManageControls(
            target: FamilyChildMemberTarget(memberUserId: "member-1", displayName: "Alex"),
            isChild: false,
            isBusy: false,
            onMarkAsChild: { _ in },
            onCorrect: { _ in },
            onOpenPrivacy: { _ in },
            onRemoveAndDelete: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Child manage controls — accessibility text size") {
    List {
        FamilyChildManageControls(
            target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
            isChild: true,
            isBusy: false,
            onMarkAsChild: { _ in },
            onCorrect: { _ in },
            onOpenPrivacy: { _ in },
            onRemoveAndDelete: { _ in }
        )
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
