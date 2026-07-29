//
//  FamilyCreatorBadge.swift
//  LicensePlateApp
//
//  Text earmark for the family founder (Captain who created the family).
//

import SwiftUI

struct FamilyCreatorBadge: View {
    var body: some View {
        Text("family.role.creator_badge".localized)
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(Color.Theme.primaryBlue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.Theme.accentYellow.opacity(0.35))
            )
            .accessibilityHidden(true)
    }
}

#Preview("Creator Captain vs Captain") {
    List {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview Driver")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text("Captain".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            Spacer()
            FamilyCreatorBadge()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview Driver, Captain, \("family.a11y.creator_badge".localized)")

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview Passenger")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text("Captain".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview Passenger, Captain")
    }
}
