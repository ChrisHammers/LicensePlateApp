//
//  UsernameProfanityFilter.swift
//  LicensePlateApp
//

import Foundation

/// Local FCC-style profanity check for usernames across English, Spanish, and French.
enum UsernameProfanityFilter {
    /// Returns `true` when the username contains a blocked term in any supported language.
    static func containsProfanity(_ username: String) -> Bool {
        let normalized = normalizedForScan(username)
        guard !normalized.isEmpty else { return false }
        return blockedTerms.contains { normalized.contains($0) }
    }

  private static let blockedTerms: [String] = {
        let english = [
            "asshole", "bastard", "bitch", "bollocks", "cocksucker", "cunt",
            "fuck", "motherfucker", "piss", "pussy", "shit", "slut", "tits",
            "twat", "wanker", "whore"
        ]
        let spanish = [
            "cabron", "carajo", "cojones", "coño", "cono", "gilipollas", "joder",
            "maricon", "mierda", "pendejo", "polla", "puta", "puto", "verga", "zorra"
        ]
        let french = [
            "bite", "bordel", "chiasse", "connard", "connasse", "couille", "encule",
            "foutre", "merde", "nique", "putain", "pute", "salope"
        ]
        return (english + spanish + french).map { normalizedForScan($0) }
    }()

    private static func normalizedForScan(_ value: String) -> String {
        let folded = value.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let leet = applyLeetSubstitutions(folded)
        return leet.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func applyLeetSubstitutions(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)

        for character in value {
            switch character {
            case "@", "4":
                result.append("a")
            case "3":
                result.append("e")
            case "1", "!":
                result.append("i")
            case "0":
                result.append("o")
            case "5", "$":
                result.append("s")
            case "7":
                result.append("t")
            default:
                result.append(character)
            }
        }

        return result
    }
}

enum UsernameValidation {
    enum Failure {
        case empty
        case profanity
    }

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func failure(for raw: String) -> Failure? {
        let trimmed = trimmed(raw)
        if trimmed.isEmpty { return .empty }
        if UsernameProfanityFilter.containsProfanity(trimmed) { return .profanity }
        return nil
    }
}
