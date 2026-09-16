//
//  AdoptDeviceTransferSheet.swift
//  LicensePlateApp
//
//  COPPA v3 FR-84 (F-41) — the CHILD's side of a device transfer, on the new device.
//
//  Chrome deliberately mirrors `JoinFamilySheet`: the same uppercase code field, the same
//  inline-error-plus-alert pair, the same busy label. A child who has entered a family code
//  before should recognise this screen immediately, because the two are the same act from the
//  child's point of view — "a grown-up gave me a code".
//
//  What it does NOT copy is the QR scanner. A transfer code assumes an account, and a scanner
//  turns any screen or printout in the room into a way to enter one; the guardian is standing
//  next to the child by construction, so typing six characters costs nothing and closes that.
//
//  Visible-but-explained, per the house child-gate style: the screen says plainly what will
//  happen to the old device, because a child who is surprised by their other tablet signing
//  out will ask an adult, and the adult should already have been told.
//
//  Analytics: NONE. This surface exists only on a child's device, so any event it emitted —
//  including a failure event — would be the FR-21 shape exactly.
//

import SwiftUI

struct AdoptDeviceTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FirebaseAuthService
    @StateObject private var viewModel = AdoptDeviceTransferViewModel()

    /// Who is holding the device. `.child`: the child's own new device (the original FR-84
    /// surface). `.adult`: a registered adult who is not the guardian — the other parent, a
    /// grandparent — setting this device up for a child with the code the guardian created
    /// (owner follow-up 2026-09-10). Same act, different reader; only the copy changes.
    enum Context {
        case child
        case adult
    }

    var context: Context = .child
    /// Fired once the device has become the child, before the sheet dismisses — onboarding
    /// uses it to continue as an existing account instead of asking a fresh child to set up.
    var onAdopted: (() -> Void)? = nil

    private var titleKey: String {
        context == .adult ? "child_gate.transfer.adult.title" : "child_gate.transfer.title"
    }

    private var explanationKey: String {
        context == .adult ? "child_gate.transfer.adult.explanation" : "child_gate.transfer.explanation"
    }

    private var oldDeviceNoticeKey: String {
        context == .adult ? "child_gate.transfer.adult.old_device_notice" : "child_gate.transfer.old_device_notice"
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    explanationSection
                    codeSection
                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .disabled(viewModel.isRedeeming)
            }
            .navigationTitle(titleKey.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.adopt()
                    } label: {
                        InviteActionLabel(
                            title: "child_gate.transfer.submit".localized,
                            isBusy: viewModel.isRedeeming,
                            busyKind: .join
                        )
                    }
                    .disabled(!viewModel.canSubmit || !authService.isOnline)
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear { viewModel.configure(authService: authService) }
            .onChange(of: viewModel.enteredCode) { _, _ in
                viewModel.normalizeEnteredCode()
            }
            .onChange(of: viewModel.didAdopt) { _, adopted in
                if adopted {
                    onAdopted?()
                    dismiss()
                }
            }
        }
    }

    private var explanationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(explanationKey.localized)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(oldDeviceNoticeKey.localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private var codeSection: some View {
        Section {
            TextField("child_gate.transfer.field_placeholder".localized, text: $viewModel.enteredCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .accessibleTextField(
                    label: "child_gate.transfer.field_label".localized,
                    hint: "child_gate.transfer.a11y.field_hint".localized,
                    value: viewModel.enteredCode
                )
        } header: {
            Text("child_gate.transfer.field_label".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        } footer: {
            Text("child_gate.transfer.field_footer".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }
}

#Preview("Adopt transfer") {
    AdoptDeviceTransferSheet()
        .environmentObject(FirebaseAuthService())
}

#Preview("Adult — setting this device up for a child") {
    AdoptDeviceTransferSheet(context: .adult)
        .environmentObject(FirebaseAuthService())
}

#Preview("Adopt transfer — dark") {
    AdoptDeviceTransferSheet()
        .environmentObject(FirebaseAuthService())
        .preferredColorScheme(.dark)
}

#Preview("Adopt transfer — large type") {
    AdoptDeviceTransferSheet()
        .environmentObject(FirebaseAuthService())
        .environment(\.dynamicTypeSize, .accessibility2)
}
