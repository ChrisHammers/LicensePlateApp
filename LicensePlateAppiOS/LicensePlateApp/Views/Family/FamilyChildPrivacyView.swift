//
//  FamilyChildPrivacyView.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-29 → FR-61): parent review surface for one flagged child — current
//  status, the LIVE data inventory from `getChildDataInventory` (guardianship-gated;
//  supersedes the old static category list), a share-sheet export, and consent history
//  from `getParentalConsentStatus`.
//
//  Read-only by design: every mutation lives back in Family Settings so a review
//  screen can never become an accidental action screen. The export is parent-initiated
//  sharing of the parent's own review, so FR-79's child share-gating does not apply.
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
        loadConsentHistory: @escaping (String) async throws -> ParentalConsentStatus,
        loadInventory: @escaping (String) async throws -> ChildDataInventory?
    ) {
        self.target = target
        self.isChild = isChild
        _viewModel = StateObject(
            wrappedValue: FamilyChildPrivacyViewModel(
                loadConsentHistory: loadConsentHistory,
                loadInventory: loadInventory
            )
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
                    inventorySections
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
                ToolbarItem(placement: .primaryAction) {
                    // FR-61 export: enabled once the live inventory loaded. A named
                    // temp file gives the share sheet a sensible default name (owner
                    // finding 2026-08-29); raw text is the fallback if the write failed.
                    if let url = viewModel.exportFileURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("family.child.inventory.export_a11y".localized)
                    } else if let text = viewModel.exportText(childDisplayName: target.displayName) {
                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("family.child.inventory.export_a11y".localized)
                    }
                }
            }
            .task(id: target.memberUserId) {
                await viewModel.load(
                    childUserId: target.memberUserId,
                    displayName: target.displayName
                )
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

    // MARK: - FR-61 live inventory

    @ViewBuilder
    private var inventorySections: some View {
        switch viewModel.inventoryState {
        case .idle, .loading:
            Section {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("family.child.inventory.loading".localized)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("family.child.inventory.loading".localized)
            } header: {
                Text("family.child.privacy_data_title".localized)
            }
            .listRowBackground(Color.Theme.cardBackground)
        case .unavailable:
            Section {
                Text("family.child.inventory.unavailable".localized)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                // Owner finding 2026-08-29: a process-level callable wedge otherwise
                // leaves reinstalling as the only visible way out — retry in place.
                Button {
                    Task {
                        await viewModel.retry(
                            childUserId: target.memberUserId,
                            displayName: target.displayName
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .accessibleDecorative()
                        Text("family.child.inventory.retry".localized)
                            .font(.system(.footnote, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(minHeight: 44, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibleButton(
                    label: "family.child.inventory.retry".localized,
                    hint: "family.child.inventory.retry_hint".localized
                )
            } header: {
                Text("family.child.privacy_data_title".localized)
            }
            .listRowBackground(Color.Theme.cardBackground)
        case .loaded(let inventory):
            identifiersSection(inventory)
            gameplaySection(inventory)
            progressSection(inventory)
            vendorsSection
        }
    }

    private func inventoryRow(_ labelKey: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(labelKey.localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func yesNo(_ value: Bool) -> String {
        (value ? "family.child.inventory.value_yes" : "family.child.inventory.value_no").localized
    }

    private func identifiersSection(_ inventory: ChildDataInventory) -> some View {
        Section {
            if let profile = inventory.profile {
                inventoryRow("family.child.inventory.username", profile.userName ?? "—")
                inventoryRow("family.child.inventory.avatar", profile.avatarId ?? "—")
                if let ageOut = profile.ageOutYearMonth,
                   let month = ExpectedAgeOutYearOptions.month(of: ageOut) {
                    inventoryRow(
                        "family.child.inventory.age_out",
                        "\(LocalizationHelper.monthName(month)) \(String(ageOut / 100))"
                    )
                }
            }
            let privateData = inventory.privateData ?? ChildDataInventory.PrivateData()
            inventoryRow("family.child.inventory.has_email", yesNo(privateData.hasEmail))
            inventoryRow("family.child.inventory.has_phone", yesNo(privateData.hasPhoneNumber))
            inventoryRow("family.child.inventory.push_token", yesNo(privateData.pushTokenPresent))
            inventoryRow(
                "family.child.inventory.searchable",
                yesNo(inventory.searchIndexes?.anyIndexed ?? false)
            )
        } header: {
            Text("family.child.privacy_data_title".localized)
        } footer: {
            Text("family.child.privacy_protections".localized)
                .font(.system(.caption, design: .rounded))
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private func gameplaySection(_ inventory: ChildDataInventory) -> some View {
        Section {
            let gameplay = inventory.gameplay ?? ChildDataInventory.Gameplay()
            inventoryRow("family.child.inventory.trip_count", String(gameplay.sessionCount))
            inventoryRow(
                "family.child.inventory.event_count",
                String(gameplay.authoredEventTotal)
            )
            inventoryRow(
                "family.child.inventory.location_payloads",
                yesNo(gameplay.anyLocationPayloadExists)
            )
            ForEach(Array(gameplay.trips.enumerated()), id: \.offset) { _, trip in
                tripRow(trip)
            }
            if gameplay.truncated {
                Text("family.child.inventory.trips_truncated".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("family.child.inventory.gameplay_title".localized)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private func tripRow(_ trip: ChildInventoryTripSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.tripName ?? "family.child.inventory.unnamed_trip".localized)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            HStack(spacing: 8) {
                if let createdAt = trip.createdAt {
                    Text(Self.recordDateFormatter.string(from: createdAt))
                }
                Text(
                    "family.child.inventory.trip_events".localized(
                        String(trip.authoredEventCountsByKind.values.reduce(0, +))
                    )
                )
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func progressSection(_ inventory: ChildDataInventory) -> some View {
        Section {
            inventoryRow("family.child.inventory.total_xp", String(inventory.totalXp ?? 0))
            inventoryRow(
                "family.child.inventory.achievements",
                String(inventory.achievementCount)
            )
            inventoryRow(
                "family.child.inventory.friend_links",
                String(inventory.friendEdgeCount)
            )
        } header: {
            Text("family.child.inventory.progress_title".localized)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    private var vendorsSection: some View {
        Section {
            Text("family.child.inventory.vendor_revenuecat".localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
            Text("family.child.inventory.vendor_analytics".localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("family.child.inventory.vendors_title".localized)
        }
        .listRowBackground(Color.Theme.cardBackground)
    }

    // MARK: - Consent history (FR-29 SHOULD half)

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

#Preview("Child privacy — inventory + history loaded") {
    FamilyChildPrivacyView(
        target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
        isChild: true,
        loadConsentHistory: { _ in
            ParentalConsentStatus(records: [
                ParentalConsentRecord(
                    id: "1",
                    eventType: .granted,
                    rawEventType: ParentalConsentEventType.granted.rawValue,
                    createdAt: Date(timeIntervalSince1970: 1_770_600_000),
                    correctionReason: nil,
                    guardianAffirmed: true,
                    expectedAgeOutYearMonth: 203107
                )
            ])
        },
        loadInventory: { _ in
            var inventory = ChildDataInventory(
                accountExists: true,
                viaGuardianship: false,
                generatedAt: Date(timeIntervalSince1970: 1_787_000_000)
            )
            inventory.profile = .init(userName: "KidRacer", avatarId: "fox", ageOutYearMonth: 203107)
            inventory.privateData = .init(pushTokenPresent: true)
            inventory.searchIndexes = .init()
            inventory.totalXp = 320
            inventory.achievementCount = 4
            var gameplay = ChildDataInventory.Gameplay()
            gameplay.sessionCount = 1
            gameplay.authoredEventTotal = 12
            gameplay.trips = [
                ChildInventoryTripSummary(
                    tripName: "Summer trip",
                    status: "ended",
                    createdAt: Date(timeIntervalSince1970: 1_786_000_000),
                    endedAt: nil,
                    authoredEventCountsByKind: ["region_found": 12],
                    attributedEventCount: 12,
                    anyLocationPayload: false
                )
            ]
            inventory.gameplay = gameplay
            return inventory
        }
    )
}

#Preview("Child privacy — inventory unavailable, dark") {
    FamilyChildPrivacyView(
        target: FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam"),
        isChild: true,
        loadConsentHistory: { _ in throw NSError(domain: "preview", code: 1) },
        loadInventory: { _ in throw NSError(domain: "preview", code: 1) }
    )
    .preferredColorScheme(.dark)
}
