//
//  FriendsFamilyInviteAnalytics.swift
//  LicensePlateApp
//
//  Maps Friends & Family callable failures to typed analytics events.
//

import Foundation
import FirebaseFunctions

enum FriendsFamilyInviteAnalytics {
    /// Logs invite / share-code failure events inferred from Cloud Function errors.
    static func logInviteFailure(_ error: Error) {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        let lower = description.lowercased()
        let functionsCode = nsError.domain == FunctionsErrorDomain
            ? FunctionsErrorCode(rawValue: nsError.code)
            : nil

        if lower.contains("friend cap") {
            AnalyticsService.shared.log(.friendCapReached)
            return
        }

        if lower.contains("already") && lower.contains("family") {
            AnalyticsService.shared.log(.inviteAutoRejectedUserAlreadyInFamily)
            return
        }

        if lower.contains("not searchable") {
            AnalyticsService.shared.log(.inviteAutoRejectedNotSearchable)
            return
        }

        if lower.contains("code expired") || lower == "code expired" {
            AnalyticsService.shared.log(.shareCodeExpired)
            return
        }

        switch functionsCode {
        case .resourceExhausted:
            AnalyticsService.shared.log(.inviteFailedRateLimited)
        case .permissionDenied:
            AnalyticsService.shared.log(.inviteFailedPermissionDenied)
        default:
            if lower.contains("permission-denied") || lower.contains("permission denied") {
                AnalyticsService.shared.log(.inviteFailedPermissionDenied)
            } else if lower.contains("rate") {
                AnalyticsService.shared.log(.inviteFailedRateLimited)
            }
        }
    }
}
