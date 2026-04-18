//
//  XpDeltaPillView.swift
//  LicensePlateApp
//

import SwiftUI

struct XpDeltaPillView: View {
    let text: String
    var isPendingStyle: Bool = false

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(isPendingStyle ? Color.Theme.primaryBlue : Color.Theme.softBrown)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isPendingStyle ? Color.Theme.accentYellow.opacity(0.35) : Color.Theme.cardBackground)
            )
            .accessibilityLabel(text)
    }
}

#Preview("Pending style") {
    XpDeltaPillView(text: "+10 XP pending", isPendingStyle: true)
        .padding()
}

#Preview("Final style") {
    XpDeltaPillView(text: "+4 XP", isPendingStyle: false)
        .padding()
}
