//
//  FamilyChildPrivacyView.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-29): read-only parent review surface for one flagged child —
//  current status, the localized static summary of held data categories (mirroring
//  Privacy Policy §12), and consent history from `getParentalConsentStatus`.
//
//  Read-only by design: every mutation lives back in Family Settings so a review
//  screen can never become an accidental action screen.
//

import SwiftUI

struct FamilyChildPrivacyView: View {
    let target: FamilyChildMemberTarget
    let isChild: Bool
    @StateObject private var viewModel: FamilyChildPrivacyViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        target: FamilyChildMemberTarget,
        isChild: Bool,
        loadConsentHistory: @escaping (String) async throws -> ParentalConsentStatus
    ) {
        self.target = target
        self.isChild = isChild
        _viewModel = StateObject(
            wrappedValue: FamilyChildPrivacyViewModel(loadConsentHistory: loadConsentHistory)
        )
    }

    private static let recordDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    statusSection
                    heldDataSection
                    consentHistorySection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("family.child.privacy_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
            .task(id: target.memberUserId) {
                await viewModel.load(childUserId: target.memberUserId)
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isChild ? "figure.child" : "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibleDecorative()
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(
                        (isChild
                            ? "family.child.privacy_status_child"
                            : "family.child.privacy_status_not_child").localized
                    )
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private var heldDataSection: some View {
        Section {
            ForEach(Self.heldDataKeys, id: \.self) { key in
                Text(key.localized)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("family.child.privacy_data_title".localized)
        } footer: {
            Text("family.child.privacy_protections".localized)
                .font(.system(.caption, design: .rounded))
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    /// Mirrors the Privacy Policy §12 categories. Static copy — never a live inventory.
    private static let heldDataKeys = [
        "family.child.privacy_data_profile",
        "family.child.privacy_data_activity",
        "family.child.privacy_data_discoveries",
        "family.child.privacy_data_stats"
    ]

    @ViewBuilder
    private var consentHistorySection: some View {
        Section {
            switch viewModel.historyState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("family.child.privacy_consent_loading".localized)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("family.child.privacy_consent_loading".localized)
            case .unavailable:
                Text("family.child.privacy_consent_unavailable".localized)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            case .loaded(let records) where records.isEmpty:
                Text("family.child.privacy_consent_empty".localized)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            case .loaded:
                ForEach(viewModel.recordsNewestFirst) { record in
                    consentRow(record)
                }
            }
        } header: {
            Text("family.child.privacy_consent_title".localized)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private func consentRow(_ record: ParentalConsentRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.localizedTitle)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            if let createdAt = record.createdAt {
                Text(Self.recordDateFormatter.string(from: createdAt))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            if let reason = record.localizedCorrectionReason {
                Text(reason)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            if record.guardianAffirmed == true {
                Text("family.child.consent_affirmed".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let yearMonth = record.expectedAgeOutYearMonth,
               let month = ExpectedAgeOutYearOptions.month(of: yearMonth) {
                Text(
                    "family.child.consent_age_out".localized(
                        "\(LocalizationHelper.monthName(month)) \(String(yearMonth / 100))"
                    )
                )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Child privacy — history loaded") {
    FamilyChildPrivacyView(
        target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
        isChild: true,
        loadConsentHistory: { _ in
            ParentalConsentStatus(records: [
                ParentalConsentRecord(
                    id: "1",
                    eventType: .declared,
                    rawEventType: ParentalConsentEventType.declared.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1_770_000_000),
                    correctionReason: nil,
                    guardianAffirmed: nil,
                    expectedAgeOutYearMonth: nil
                ),
                ParentalConsentRecord(
                    id: "2",
                    eventType: .granted,
                    rawEventType: ParentalConsentEventType.granted.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1_770_600_000),
                    correctionReason: nil,
                    guardianAffirmed: true,
                    expectedAgeOutYearMonth: 2031
                )
            ])
        }
    )
}

#Preview("Child privacy — history unavailable, dark") {
    FamilyChildPrivacyView(
        target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
        isChild: true,
        loadConsentHistory: { _ in
            throw NSError(domain: "preview", code: 1)
        }
    )
    .preferredColorScheme(.dark)
}
