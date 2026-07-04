//
//  XpPendingBadgeView.swift
//  LicensePlateApp
//

import SwiftUI

struct RegionRowStatusBadgeView: View {
    let text: String
    let style: RegionPlateRowStatusStyle
    var accessibilityLabel: String? = nil

    private var iconName: String? {
        switch style {
        case .pending:
            return "clock.badge.questionmark"
        case .firstFinder:
            return "medal.fill"
        case .acceptedLate:
            return "person.2.fill"
        case .adjustedAfterSync:
            return "arrow.triangle.2.circlepath"
        case .informational:
            return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch style {
        case .pending:
            return Color.Theme.primaryBlue
        case .firstFinder:
            return Color.Theme.accentYellow
        case .acceptedLate:
            return Color.Theme.permissionOrange
        case .adjustedAfterSync:
            return Color.Theme.permissionOrangeDark
        case .informational:
            return Color.Theme.primaryBlue
        }
    }

    private var textColor: Color {
        switch style {
        case .pending:
            return Color.Theme.softBrown
        case .firstFinder:
            return Color.Theme.primaryBlue
        case .acceptedLate:
            return Color.Theme.permissionOrange
        case .adjustedAfterSync:
            return Color.Theme.permissionOrangeDark
        case .informational:
            return Color.Theme.primaryBlue
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .pending:
            return Color.Theme.accentYellow.opacity(0.24)
        case .firstFinder:
            return Color.Theme.accentYellow.opacity(0.20)
        case .acceptedLate:
            return Color.Theme.permissionOrange.opacity(0.12)
        case .adjustedAfterSync:
            return Color.Theme.permissionOrangeDark.opacity(0.12)
        case .informational:
            return Color.Theme.primaryBlue.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch style {
        case .pending:
            return Color.Theme.primaryBlue.opacity(0.35)
        case .firstFinder:
            return Color.Theme.accentYellow.opacity(0.65)
        case .acceptedLate:
            return Color.Theme.permissionOrange.opacity(0.50)
        case .adjustedAfterSync:
            return Color.Theme.permissionOrangeDark.opacity(0.50)
        case .informational:
            return Color.Theme.primaryBlue.opacity(0.35)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? text)
    }
}

struct XpPendingBadgeView: View {
    var body: some View {
        RegionRowStatusBadgeView(
            text: "xp.pending.badge.short".localized,
            style: .pending,
            accessibilityLabel: "xp.pending.badge.a11y".localized
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        XpPendingBadgeView()
        RegionRowStatusBadgeView(text: "First finder".localized, style: .firstFinder)
        RegionRowStatusBadgeView(text: "xp.discovery.badge.accepted_late".localized, style: .acceptedLate)
        RegionRowStatusBadgeView(text: "xp.discovery.badge.adjusted_after_sync".localized, style: .adjustedAfterSync)
    }
    .padding()
}
