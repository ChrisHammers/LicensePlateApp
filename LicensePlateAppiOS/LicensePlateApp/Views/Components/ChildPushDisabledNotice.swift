//
//  ChildPushDisabledNotice.swift
//  LicensePlateApp
//
//  COPPA F-29 (FR-73(b)): shown in place of the notification permission row while the
//  session may hold no FCM token. Rendered projection only — the suppression happens in
//  `FirebaseMessagingService` at the eligibility seam, never from a view.
//
//  Deliberately the same shape as `ChildLocationDisabledNotice` (FR-33): same row layout,
//  same typography, same "the wording carries the state, the icon only reinforces it"
//  discipline. One new string, because unlike location there is only one cause — an
//  unconsented child. A CONSENTED child keeps the permission row: family-trip pushes are
//  exactly what their parent consented to.
//

import SwiftUI

struct ChildPushDisabledNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)
            Text("child_gate.notifications_disabled".localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Child push notice") {
    ChildPushDisabledNotice()
        .padding()
        .background(Color.Theme.cardBackground)
}

#Preview("Child push notice — dark") {
    ChildPushDisabledNotice()
        .padding()
        .background(Color.Theme.cardBackground)
        .preferredColorScheme(.dark)
}
