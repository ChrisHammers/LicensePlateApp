//
//  ContactSearchNormalization.swift
//  LicensePlateApp
//
//  Client-side email/phone normalization for private/contact + userNameLower.
//  Server (libphonenumber) remains authoritative for search lookups.
//

import Foundation

enum ContactSearchNormalization {
    static func emailLower(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return nil
        }
        return email.lowercased()
    }

    /// Best-effort US E.164 for dual-write; Cloud Functions re-normalize with libphonenumber.
    static func phoneE164US(_ phone: String?) -> String? {
        guard let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty else {
            return nil
        }
        let digits = phone.filter(\.isNumber)
        if phone.contains("+"), digits.count >= 10 {
            return "+\(digits)"
        }
        if digits.count == 10 {
            return "+1\(digits)"
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }
        return nil
    }

    static func userNameLower(_ userName: String) -> String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
