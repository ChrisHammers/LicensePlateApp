//
//  AgeGateView.swift
//  LicensePlateApp
//
//  COPPA F-6 (FR-27 amended): the neutral age screen. Presents a birth-year picker
//  with no visible incentive to answer either way; the year is used only to derive
//  the category and is never stored (D-3). Renders projections only — derivation and
//  persistence live in AgeGateViewModel / AgeGateStore.
//

import SwiftUI

struct AgeGateView: View {
    @StateObject private var viewModel: AgeGateViewModel
    private let onComplete: () -> Void

    init(source: AgeGateSource, onComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: AgeGateViewModel(source: source))
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "calendar")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleDecorative()

                    Text("age_gate.title".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                        .accessibleHeader("age_gate.title".localized)

                    Text("age_gate.subtitle".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    birthYearCard
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                Button {
                    submit()
                } label: {
                    Text("Continue".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.Theme.primaryBlue))
                        .foregroundStyle(.white)
                }
                .accessibleButton(
                    label: "Continue".localized,
                    hint: "age_gate.continue_hint".localized
                )
                .disabled(!viewModel.canContinue)
                .opacity(viewModel.canContinue ? 1 : 0.6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onAppear {
            viewModel.recordShown()
        }
    }

    private var birthYearCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // FR-55 (v3.7): month + year, both neutral — no default selection, nothing
            // signals a cutoff. The day is deliberately never asked for (minimization);
            // the residual birthday-month ambiguity classifies protectively in the store.
            HStack {
                Text("age_gate.month_label".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer(minLength: 12)

                Picker("age_gate.month_label".localized, selection: $viewModel.selectedBirthMonth) {
                    Text("age_gate.month_placeholder".localized)
                        .tag(Int?.none)
                    ForEach(viewModel.monthOptions, id: \.self) { month in
                        Text(verbatim: viewModel.monthName(month))
                            .tag(Int?.some(month))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.Theme.primaryBlue)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("age_gate.picker_hint_month".localized)
                .accessibilityValue(
                    viewModel.selectedBirthMonth.map { viewModel.monthName($0) }
                        ?? "age_gate.month_placeholder".localized
                )
            }

            HStack {
                Text("age_gate.year_label".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer(minLength: 12)

                Picker("age_gate.year_label".localized, selection: $viewModel.selectedBirthYear) {
                    Text("age_gate.year_placeholder".localized)
                        .tag(Int?.none)
                    ForEach(viewModel.yearOptions, id: \.self) { year in
                        Text(verbatim: String(year))
                            .tag(Int?.some(year))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.Theme.primaryBlue)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("age_gate.picker_hint".localized)
                .accessibilityValue(
                    viewModel.selectedBirthYear.map { String($0) }
                        ?? "age_gate.year_placeholder".localized
                )
            }

            Text("age_gate.privacy_note".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func submit() {
        guard viewModel.submit() else { return }
        FeedbackService.shared.buttonTap()
        onComplete()
    }
}

#Preview("Age gate — light") {
    AgeGateView(source: .launch, onComplete: {})
        .background(Color.Theme.background)
}

#Preview("Age gate — dark") {
    AgeGateView(source: .launch, onComplete: {})
        .background(Color.Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Age gate — XXL type") {
    AgeGateView(source: .registration, onComplete: {})
        .background(Color.Theme.background)
        .environment(\.dynamicTypeSize, .accessibility3)
}
