//
//  FamilyChildBadge.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-20/FR-22): read-only "Child" marker on family member rows.
//  Icon + TEXT — child status is never conveyed by color alone. The badge itself is
//  hidden from VoiceOver; each row folds the status into its own combined label so
//  the reading order stays "name, handle, role, child account".
//

import SwiftUI

struct FamilyChildBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.child")
                .font(.system(size: 11, weight: .semibold))
            Text("family.child.badge".localized)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.Theme.primaryBlue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.Theme.primaryBlue.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.Theme.primaryBlue.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

#Preview("Child badge — light") {
    List {
        HStack {
            Text("Sam")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Spacer()
            FamilyChildBadge()
        }
        HStack {
            Text("Alex")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Spacer()
            FamilyCreatorBadge()
            FamilyChildBadge()
        }
    }
}

#Preview("Child badge — dark, accessibility size") {
    List {
        HStack {
            Text("Sam")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Spacer()
            FamilyChildBadge()
        }
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
