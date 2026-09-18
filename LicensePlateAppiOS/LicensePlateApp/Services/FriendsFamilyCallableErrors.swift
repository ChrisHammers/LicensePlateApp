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
    /// F-18 (FR-60(b)): the consent exit was reached before the child's uid was minted.
    /// Retryable and local — never the "sign in" copy, which FR-60(e) makes unfollowable for
    /// a child. Shared with `AuthError.childDeclarationPending` so one condition has one voice.
    static let childSetupIncompleteMessageKey = "child_gate.join.setup_incomplete"

    /// The one fact about the caller's session that `map` consults, lifted out of the live
    /// `Auth.auth().currentUser` read so the mapping is a pure function of (error, session).
    /// The hosted test used to read the live session inside the test host and flipped with
    /// whatever guest the simulator's last `--skipOnboarding` UI run had left in the keychain
    /// (observed both ways 2026-09-08..12).
    ///
    /// Item 11 of SRS §3.1.1: "registered" means `SessionCredentialPolicy.isCredentialed` —
    /// non-anonymous AND provider-backed — so the FR-84 custom-token (transferred child)
    /// session classifies as `.uncredentialed`, exactly as `AccountState` and the pre-call
    /// gate (`FriendsFamilyAccessPolicy`) classify it and as the server's
    /// `assertRegisteredAccount` refuses it.
    enum SessionKind {
        /// `Auth.auth().currentUser == nil`.
        case signedOut
        /// A live session with no credential its holder could sign back in with: an
        /// anonymous guest or a custom-token (transferred child) session. Gets the guest copy.
        case uncredentialed
        /// A provider-backed sign-in — a registered account.
        case credentialed

        /// Classifies a PRESENT session from the two facts `SessionCredentialPolicy` reads.
        /// `.signedOut` is the absence of a session and is never produced here.
        static func classify(isAnonymous: Bool, providerCount: Int) -> SessionKind {
            SessionCredentialPolicy.isCredentialed(isAnonymous: isAnonymous, providerCount: providerCount)
                ? .credentialed
                : .uncredentialed
        }

        /// What `Auth.auth().currentUser` says right now — the production default.
        static var live: SessionKind {
            guard let user = Auth.auth().currentUser else { return .signedOut }
            return classify(isAnonymous: user.isAnonymous, providerCount: user.providerData.count)
        }
    }

    static var guestBlockedMessage: String {
        guestBlockedMessageKey.localized
    }

    static var childSetupIncompleteMessage: String {
        childSetupIncompleteMessageKey.localized
    }

    static var recipientNotRegisteredMessage: String {
        recipientNotRegisteredMessageKey.localized
    }

    static var childRestrictionMessage: String {
        childRestrictionMessageKey.localized
    }

    /// Maps a Cloud Functions error to user-facing copy. `session` defaults to the live
    /// Firebase session; tests pass a kind explicitly so the mapping never depends on the
    /// test host's keychain.
    static func map(_ error: Error, session: SessionKind = .live) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }

        // The child-copy branch stays FIRST: a child-restriction rejection gets the same
        // non-punitive copy for every session kind (F-6 / FR-28).
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
            switch session {
            case .signedOut:
                message = "You are not signed in. Sign in and try again.".localized
            case .uncredentialed:
                message = guestBlockedMessage
            case .credentialed:
                message = "The server rejected this request. Sign in and try again.".localized
            }
        case .failedPrecondition:
            if case .uncredentialed = session {
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
