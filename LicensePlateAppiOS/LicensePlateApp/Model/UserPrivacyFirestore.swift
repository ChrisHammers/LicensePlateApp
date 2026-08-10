//
//  UserPrivacyFirestore.swift
//  LicensePlateApp
//
//  Firestore privacy envelope shared by profile write/read paths.
//  Search + Cloud Functions read `privacy.emailSearchable` / `phoneSearchable`.
//

import Foundation
import FirebaseFirestore

enum UserPrivacyFirestore {
    static func encode(isEmailPublic: Bool, isPhonePublic: Bool) -> [String: Bool] {
        [
            "emailSearchable": isEmailPublic,
            "phoneSearchable": isPhonePublic
        ]
    }

    /// Prefer `privacy.*`; fall back to legacy top-level `isEmailPublic` / `isPhonePublic`.
    static func decode(from data: [String: Any]) -> (isEmailPublic: Bool, isPhonePublic: Bool) {
        let privacy = data["privacy"] as? [String: Any]
        let isEmailPublic = privacy?["emailSearchable"] as? Bool
            ?? data["isEmailPublic"] as? Bool
            ?? false
        let isPhonePublic = privacy?["phoneSearchable"] as? Bool
            ?? data["isPhonePublic"] as? Bool
            ?? false
        return (isEmailPublic, isPhonePublic)
    }
}

/// Contact containment for OAuth-linked platforms (FR-43 / audit E1).
///
/// `users/{uid}` is peer-readable, so linked-platform entries there carry platform
/// identity only. Provider-supplied `email` / `phoneNumber` / `displayName` live under
/// `users/{uid}/private/contact.linkedPlatforms`, which only the owner can read.
/// The local SwiftData `LinkedPlatform` struct is unchanged; the split is serialization-only.
enum LinkedPlatformFirestore {
    /// The only keys allowed on a peer-readable `users/{uid}.linkedPlatforms` entry.
    static let publicEntryKeys: Set<String> = ["platform", "platformUserId", "linkedAt"]

    /// Contact-bearing keys that must never reach the public profile document.
    static let contactEntryKeys: Set<String> = ["email", "phoneNumber", "displayName"]

    /// Sanitized entries for the peer-readable profile document.
    static func publicEntries(from platforms: [LinkedPlatform]) -> [[String: Any]] {
        platforms.map { platform in
            [
                "platform": platform.platform.rawValue,
                "platformUserId": platform.platformUserId,
                "linkedAt": Timestamp(date: platform.linkedAt)
            ]
        }
    }

    /// Owner-only rows for `users/{uid}/private/contact.linkedPlatforms`.
    /// - Returns: `nil` when no linked platform carries a contact identifier (nothing to write).
    static func privateContactEntries(from platforms: [LinkedPlatform]) -> [[String: Any]]? {
        let entries: [[String: Any]] = platforms.compactMap { platform in
            var entry: [String: Any] = [:]
            if let email = platform.email, !email.isEmpty {
                entry["email"] = email
            }
            if let phoneNumber = platform.phoneNumber, !phoneNumber.isEmpty {
                entry["phoneNumber"] = phoneNumber
            }
            if let displayName = platform.displayName, !displayName.isEmpty {
                entry["displayName"] = displayName
            }
            guard !entry.isEmpty else { return nil }
            entry["platform"] = platform.platform.rawValue
            entry["platformUserId"] = platform.platformUserId
            return entry
        }
        return entries.isEmpty ? nil : entries
    }

    /// Rehydrates owner-side contact onto platforms parsed from the public document.
    /// Values already present locally win (never downgrade a fresher local link).
    static func merging(
        _ platforms: [LinkedPlatform],
        privateEntries: [[String: Any]]?
    ) -> [LinkedPlatform] {
        guard let privateEntries, !privateEntries.isEmpty else { return platforms }

        var contactByPlatform: [String: [String: Any]] = [:]
        for entry in privateEntries {
            guard let key = entry["platform"] as? String else { continue }
            contactByPlatform[key] = entry
        }

        return platforms.map { platform in
            guard let entry = contactByPlatform[platform.platform.rawValue] else { return platform }
            var merged = platform
            if merged.email == nil, let email = entry["email"] as? String, !email.isEmpty {
                merged.email = email
            }
            if merged.phoneNumber == nil, let phone = entry["phoneNumber"] as? String, !phone.isEmpty {
                merged.phoneNumber = phone
            }
            if merged.displayName == nil, let name = entry["displayName"] as? String, !name.isEmpty {
                merged.displayName = name
            }
            return merged
        }
    }
}
