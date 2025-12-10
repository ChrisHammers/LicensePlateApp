//
//  PublicTripRow.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct PublicTripRow: View {
    let trip: Trip

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trip.name)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer()

              Label("\(trip.foundRegionIDs.count)/\(PlateRegion.all.count)", systemImage: "licenseplate")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibilityLabel("Progress: \(trip.foundRegionIDs.count) of \(PlateRegion.all.count) regions found")
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))
                .accessibilityHidden(true)

            HStack {
              Label(trip.startedAt != nil ? "Started".localized :"Created".localized, systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel(trip.startedAt != nil ? "Started".localized : "Created".localized)

                Spacer()

              Text(dateFormatter.string(from: trip.startedAt != nil ? trip.startedAt! : trip.createdAt))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Date: \(dateFormatter.string(from: trip.startedAt != nil ? trip.startedAt! : trip.createdAt))")
            }
            
            // Show "Ended on" date if trip has ended
            if trip.isTripEnded, let endedDate = trip.tripEndedAt {
                HStack {
                  Label {
                      Text("Ended".localized)
                              } icon: {
                                      Image(systemName: "star.fill")
                                          .font(.body)
                                          .opacity(0)
                              }
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Ended".localized)

                    Spacer()

                    Text(dateFormatter.string(from: endedDate))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Date: \(dateFormatter.string(from: endedDate))")
                }
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
    }
}

