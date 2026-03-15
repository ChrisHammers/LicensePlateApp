//
//  TripSessionRow.swift
//  LicensePlateApp
//
//  Step 12 — Row for a TripSession when no backing Trip is available for display (e.g. session-only flows).
//

import SwiftUI

/// Displays a single TripSession in the active list when TripRow cannot be used (no Trip loaded for session.id).
struct TripSessionRow: View {
    let session: TripSession
    /// Number of license plates / regions found for this trip (from TripActivityEventRepository).
    var plateCount: Int = 0

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var dateLabel: String {
        if let started = session.startedAt {
            return dateFormatter.string(from: started)
        }
        return dateFormatter.string(from: session.createdAt)
    }

    private var dateCaption: String {
        session.startedAt != nil ? "Started".localized : "Created".localized
    }

    /// Builds LicensePlateGameConfig from the session's enabled countries (same scope/territory logic as CombinedGameAssembler) and returns the total number of regions available for the license plate game.
    private var licensePlateTotalAvailable: Int {
        let config = licensePlateConfig(from: session)
        return LicensePlateScopeCalculator.completionGoal(for: config)
    }

    /// License plate config derived from session.enabledCountries. Matches CombinedGameAssembler defaults (regionScope from countries; include DC, US territories, Canadian territories).
    private func licensePlateConfig(from session: TripSession) -> LicensePlateGameConfig {
        let scope = regionScope(from: session.enabledCountries)
        let territoryOptions = LicensePlateTerritoryOptions(
            includeUSTerritories: true,
            includeCanadianTerritories: true,
            includeDC: true
        )
        return LicensePlateGameConfig(regionScope: scope, territoryOptions: territoryOptions)
    }

    private func regionScope(from countries: [PlateRegion.Country]) -> RegionScope {
        let set = Set(countries)
        if set == [.unitedStates] { return .usOnly }
        if set == [.canada] { return .canadaOnly }
        if set == [.mexico] { return .mexicoOnly }
        return .northAmerica
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.name)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer()

                Label("\(plateCount)/\(licensePlateTotalAvailable)", systemImage: "licenseplate")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel(plateCount == 1 ? "1 license plate found".localized : "%d license plates found".localized(plateCount))
                    .accessibilityValue("%d of %d".localized(plateCount, licensePlateTotalAvailable))
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))
                .accessibilityHidden(true)

            HStack {
                Label(dateCaption, systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel(dateCaption)

                Spacer()

                Text(dateLabel)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Date: \(dateLabel)".localized)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip: %@".localized(session.name))
        .accessibilityHint("Double tap to open trip".localized)
    }
}

#Preview("Solo trip") {
    List {
        TripSessionRow(session: PreviewTripFixtures.soloTrip())
    }
    .listStyle(.insetGrouped)
}

#Preview("Completed trip") {
    List {
        TripSessionRow(session: PreviewTripFixtures.completedTrip())
    }
    .listStyle(.insetGrouped)
}
