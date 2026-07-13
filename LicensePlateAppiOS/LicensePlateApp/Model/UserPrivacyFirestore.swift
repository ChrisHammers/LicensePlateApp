//
//  UserPrivacyFirestore.swift
//  LicensePlateApp
//
//  Firestore privacy envelope shared by profile write/read paths.
//  Search + Cloud Functions read `privacy.emailSearchable` / `phoneSearchable`.
//

import Foundation

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
