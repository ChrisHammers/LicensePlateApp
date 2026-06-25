//
//  TripEndedRemoteToastBanner.swift
//  LicensePlateApp
//
//  In-app toast when another participant ends the trip.
//

import SwiftUI

struct TripEndedRemoteToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(Color.Theme.primaryBlue)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.Theme.cardBackground)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isStaticText)
    }
}
