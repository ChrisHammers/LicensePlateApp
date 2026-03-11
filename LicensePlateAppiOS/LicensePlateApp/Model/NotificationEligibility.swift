//
//  NotificationEligibility.swift
//  LicensePlateApp
//
//  Step 08 — Lightweight eligibility model for notifications. No persistence; permission-based only.
//

import Foundation

/// Kind of notification we may deliver (trip invite, milestone, etc.).
enum NotificationEligibilityKind: String, CaseIterable {
    case tripInvite
    case milestone
}

/// Result of checking whether we can show a notification of a given kind (e.g. permission granted).
struct NotificationEligibility: Sendable {
    let kind: NotificationEligibilityKind
    let isEligible: Bool
    /// When not eligible, a short reason for analytics (e.g. "denied", "notDetermined").
    let denialReason: String?

    init(kind: NotificationEligibilityKind, isEligible: Bool, denialReason: String? = nil) {
        self.kind = kind
        self.isEligible = isEligible
        self.denialReason = denialReason
    }
}
