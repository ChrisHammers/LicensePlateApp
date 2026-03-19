//
//  TripMissingView.swift
//  LicensePlateApp
//
//  Shown when a trip session or game cannot be found (e.g. deleted). Used by ContentView and TripSessionView.
//

import SwiftUI

struct TripMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.Theme.accentYellow)
                .accessibilityHidden(true)
            Text("Session Unavailable".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("We could not find this trip session.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session Unavailable. We could not find this trip session.".localized)
    }
}
