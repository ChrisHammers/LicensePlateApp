//
//  ChildLocationDisabledNotice.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-33 amended): shown in place of location toggles while the session
//  may not use location. Rendered projection only — the flags are forced off in
//  `LocationSettingsService` at the posture seam, never from a view.
//
//  FR-75 amendment (OD-8): two copies, because the restriction now has two causes.
//  A child-evidenced session is told its account's options are off; a session merely
//  held for want of a fresh server read (reinstall / offline first launch) is told the
//  truth about ITS situation instead of being called a child.
//

import SwiftUI

/// Which copy the notice renders. Pure selection, same shape as
/// `ChildPremiumSheetVariant` — the view maps a projection to text and nothing else.
enum ChildLocationNoticeVariant: Equatable {
    /// A child account, a device that has hosted one, or an under-13 answer in flight.
    case childAccount
    /// Held only because this session has not been confirmed adult yet.
    case unverifiedSession

    static func variant(isChildEvidenced: Bool) -> ChildLocationNoticeVariant {
        isChildEvidenced ? .childAccount : .unverifiedSession
    }

    var messageKey: String {
        switch self {
        case .childAccount: return "child_gate.location_disabled"
        case .unverifiedSession: return "child_gate.location_unverified"
        }
    }
}

struct ChildLocationDisabledNotice: View {
    /// `ChildSessionPostureCoordinator.isLocationRestrictionChildEvidenced`. Defaults to
    /// the child copy so an un-updated call site can only ever be over-protective.
    var isChildEvidenced: Bool = true

    var variant: ChildLocationNoticeVariant {
        .variant(isChildEvidenced: isChildEvidenced)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)
            Text(variant.messageKey.localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// The wording carries the state; the icon only reinforces it (never color alone).
    private var iconName: String {
        switch variant {
        case .childAccount: return "location.slash.fill"
        case .unverifiedSession: return "location.slash"
        }
    }
}

#Preview("Child location notice") {
    ChildLocationDisabledNotice(isChildEvidenced: true)
        .padding()
        .background(Color.Theme.cardBackground)
}

#Preview("Unverified session notice") {
    ChildLocationDisabledNotice(isChildEvidenced: false)
        .padding()
        .background(Color.Theme.cardBackground)
}
