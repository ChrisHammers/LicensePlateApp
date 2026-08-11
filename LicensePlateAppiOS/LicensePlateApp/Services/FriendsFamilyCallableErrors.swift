//
//  FriendsFamilyCallableErrors.swift
//  LicensePlateApp
//
//  Shared user-facing errors for Friends & Family Cloud Function calls.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

enum FriendsFamilyCallableErrors {
    static let guestBlockedMessageKey = "Create an account to use Friends & Family features."
    static let recipientNotRegisteredServerMessage = "Recipient has not created a registered account"
    static let recipientNotRegisteredMessageKey = "Recipient has not created a registered account."
    /// F-6 (FR-28): non-punitive copy for the server's unconsented-child / child-account
    /// rejections (`details.reason`), matching the restricted-state surface.
    static let childRestrictionMessageKey = "child_gate.callable_blocked"

    static var guestBlockedMessage: String {
        guestBlockedMessageKey.localized
    }

    static var recipientNotRegisteredMessage: String {
        recipientNotRegisteredMessageKey.localized
    }

    static var childRestrictionMessage: String {
        childRestrictionMessageKey.localized
    }

    static func map(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }

        if ChildRestrictedModeService.isChildRestrictionRejection(error) {
            return NSError(
                domain: nsError.domain,
                code: nsError.code,
                userInfo: [NSLocalizedDescriptionKey: childRestrictionMessage]
            )
        }

        let message: String
        switch code {
        case .unauthenticated:
            if Auth.auth().currentUser == nil {
                message = "You are not signed in. Sign in and try again.".localized
            } else if Auth.auth().currentUser?.isAnonymous == true {
                message = guestBlockedMessage
            } else {
                message = "The server rejected this request. Sign in and try again.".localized
            }
        case .failedPrecondition:
            if Auth.auth().currentUser?.isAnonymous == true {
                message = guestBlockedMessage
            } else if nsError.localizedDescription == recipientNotRegisteredServerMessage {
                message = recipientNotRegisteredMessage
            } else if !nsError.localizedDescription.isEmpty {
                message = nsError.localizedDescription
            } else {
                message = guestBlockedMessage
            }
        default:
            return error
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
