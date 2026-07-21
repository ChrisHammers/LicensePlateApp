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

    /// Non-destructive `private/contact` merge fields.
    /// Omits missing email/phone (never writes null). Returns `nil` when there is nothing to write.
    static func privateContactMergeFields(email: String?, phoneNumber: String?) -> [String: String]? {
        var fields: [String: String] = [:]

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedEmail, !trimmedEmail.isEmpty {
            fields["email"] = trimmedEmail
            fields["emailLower"] = emailLower(trimmedEmail) ?? trimmedEmail.lowercased()
        }

        let trimmedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPhone, !trimmedPhone.isEmpty {
            fields["phoneNumber"] = trimmedPhone
            if let e164 = phoneE164US(trimmedPhone) {
                fields["phoneE164"] = e164
            }
        }

        return fields.isEmpty ? nil : fields
    }
}
