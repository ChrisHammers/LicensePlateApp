//
//  ChildLocationDisabledNotice.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-33 amended): shown in place of location toggles for child
//  sessions. Rendered projection only — the flags are forced off in
//  `LocationSettingsService` at the posture seam, never from a view.
//

import SwiftUI

struct ChildLocationDisabledNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)
            Text("child_gate.location_disabled".localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Child location notice") {
    ChildLocationDisabledNotice()
        .padding()
        .background(Color.Theme.cardBackground)
}
