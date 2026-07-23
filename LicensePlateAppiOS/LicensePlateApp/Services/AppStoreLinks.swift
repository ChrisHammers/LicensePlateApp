//
//  AppStoreLinks.swift
//  LicensePlateApp
//
//  Builds App Store product / write-review URLs from the configured Apple ID
//  (Info.plist) or a Remote Config store URL (app_update_policy_v1).
//

import Foundation

enum AppStoreLinks {
    /// Info.plist key for the numeric App Store Connect Apple ID.
    static let infoPlistAppleIDKey = "AppStoreAppleId"

    /// Numeric Apple ID from `Info.plist` (`AppStoreAppleId`). Empty until the listing exists.
    static var configuredAppleAppID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistAppleIDKey) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Write-review URL when an Apple ID can be resolved from Info.plist or a store URL string.
    static func writeReviewURL(
        appleAppID: String = configuredAppleAppID,
        storeURLString: String? = nil
    ) -> URL? {
        guard let id = resolvedAppleAppID(appleAppID: appleAppID, storeURLString: storeURLString) else {
            return nil
        }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    /// Product page URL (no write-review action).
    static func productURL(
        appleAppID: String = configuredAppleAppID,
        storeURLString: String? = nil
    ) -> URL? {
        guard let id = resolvedAppleAppID(appleAppID: appleAppID, storeURLString: storeURLString) else {
            return nil
        }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    static func resolvedAppleAppID(appleAppID: String, storeURLString: String?) -> String? {
        if let id = normalizedAppleAppID(appleAppID) {
            return id
        }
        return appleAppIDFromStoreURLString(storeURLString)
    }

    static func normalizedAppleAppID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
    }

    /// Extracts `123456789` from URLs like `https://apps.apple.com/app/id123456789`.
    static func appleAppIDFromStoreURLString(_ storeURLString: String?) -> String? {
        guard let storeURLString, !storeURLString.isEmpty else { return nil }
        guard let match = storeURLString.range(of: #"id(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let token = storeURLString[match]
        return String(token.dropFirst(2)) // drop "id"
    }
}
