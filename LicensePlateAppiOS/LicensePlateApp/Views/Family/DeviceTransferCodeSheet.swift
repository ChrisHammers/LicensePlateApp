//
//  DeviceTransferCodeSheet.swift
//  LicensePlateApp
//
//  COPPA v3 FR-84 (F-41) — the GUARDIAN's side of a device transfer.
//
//  Chrome deliberately mirrors `CreateFamilyShareCodeSheet`: monospaced code, live countdown,
//  copy button. What it does NOT copy is the QR image and the system share sheet. A share code
//  is an invitation somebody still has to approve; this code assumes a child's ACCOUNT the
//  moment it is entered, so putting it into a screenshot or an arbitrary third-party share
//  extension would be handing an account credential to whatever the child taps next. Read it
//  aloud, or copy it once — those are the two paths this sheet offers, and the omission is the
//  point.
//
//  Analytics: the mint event fires from the view model (guardian's own instance, FR-21). This
//  view logs nothing itself, per the Views-render-only rule.
//

import SwiftUI
import Combine

struct DeviceTransferCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IssueDeviceTransferCodeViewModel

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(childUserId: String, childDisplayName: String, familyId: String) {
        _viewModel = StateObject(
            wrappedValue: IssueDeviceTransferCodeViewModel(
                childUserId: childUserId,
                childDisplayName: childDisplayName,
                familyId: familyId
            )
        )
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    explanationSection
                    codeSection
                    instructionsSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("family.child.transfer.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onReceive(clock) { _ in viewModel.tickClock() }
        }
    }

    private var explanationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("family.child.transfer.explanation".localized(viewModel.childDisplayName))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                Text("family.child.transfer.old_device_warning".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    @ViewBuilder
    private var codeSection: some View {
        Section {
            if let code = viewModel.code {
                VStack(spacing: 12) {
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .textSelection(.enabled)
                        .accessibilityLabel("family.child.transfer.a11y.code".localized(code))

                    // The countdown carries its meaning in words as well as position, so the
                    // expiry is never conveyed by colour or placement alone.
                    if let remaining = viewModel.formattedTimeRemaining {
                        Text(
                            viewModel.isExpired
                                ? "family.child.transfer.expired".localized
                                : "family.child.transfer.expires_in".localized(remaining)
                        )
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel(
                            viewModel.isExpired
                                ? "family.child.transfer.expired".localized
                                : "family.child.transfer.a11y.expires_in".localized(remaining)
                        )
                    }

                    Button {
                        viewModel.copyCode()
                    } label: {
                        Label("family.child.transfer.copy".localized, systemImage: "doc.on.doc")
                            .font(.system(.subheadline, design: .rounded))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibleButton(
                        label: "family.child.transfer.copy".localized,
                        hint: "family.child.transfer.a11y.copy_hint".localized
                    )

                    // Always available (owner 2026-09-12): a spent or mis-typed code, or one the
// parent simply wants replaced, must not wait out the timer. The server
// supersedes the previous code on every mint. Busy while the mint is in flight
// (owner 2026-09-14: a slow request looked like a dead button).
Group {
                        Button {
                            viewModel.generateCode()
                        } label: {
                            Label {
                                InviteActionLabel(
                                    title: "family.child.transfer.new_code".localized,
                                    isBusy: viewModel.isGenerating,
                                    busyTitle: "Creating...".localized
                                )
                            } icon: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .font(.system(.subheadline, design: .rounded))
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isGenerating)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Button {
                    viewModel.generateCode()
                } label: {
                    InviteActionLabel(
                        title: "family.child.transfer.generate".localized,
                        isBusy: viewModel.isGenerating,
                        busyTitle: "Creating...".localized
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(viewModel.isGenerating)
                .accessibleButton(
                    label: "family.child.transfer.generate".localized,
                    hint: "family.child.transfer.a11y.generate_hint".localized
                )
            }
        } header: {
            Text("family.child.transfer.code_header".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", textKey: "family.child.transfer.step_1")
                instructionRow(number: "2", textKey: "family.child.transfer.step_2")
                instructionRow(number: "3", textKey: "family.child.transfer.step_3")
            }
            .padding(.vertical, 4)
        } header: {
            Text("family.child.transfer.steps_header".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private func instructionRow(number: String, textKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(textKey.localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Device transfer — before minting") {
    DeviceTransferCodeSheet(
        childUserId: "child-1",
        childDisplayName: "Sam",
        familyId: "fam-1"
    )
}

#Preview("Device transfer — dark") {
    DeviceTransferCodeSheet(
        childUserId: "child-1",
        childDisplayName: "Sam",
        familyId: "fam-1"
    )
    .preferredColorScheme(.dark)
}

#Preview("Device transfer — large type") {
    DeviceTransferCodeSheet(
        childUserId: "child-1",
        childDisplayName: "Sam",
        familyId: "fam-1"
    )
    .environment(\.dynamicTypeSize, .accessibility2)
}
