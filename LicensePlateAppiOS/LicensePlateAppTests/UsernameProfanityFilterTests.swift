//
//  UsernameProfanityFilterTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

struct UsernameProfanityFilterTests {

    @Test func allowsCleanUsernames() {
        #expect(!UsernameProfanityFilter.containsProfanity("RoadTripper"))
        #expect(!UsernameProfanityFilter.containsProfanity("JeanLuc"))
        #expect(!UsernameProfanityFilter.containsProfanity("Maria123"))
        #expect(!UsernameProfanityFilter.containsProfanity("ClassicDriver"))
    }

    @Test func blocksEnglishProfanity() {
        #expect(UsernameProfanityFilter.containsProfanity("fuck"))
        #expect(UsernameProfanityFilter.containsProfanity("shithead"))
        #expect(UsernameProfanityFilter.containsProfanity("f_u_c_k"))
        #expect(UsernameProfanityFilter.containsProfanity("f4ck"))
    }

    @Test func blocksSpanishProfanity() {
        #expect(UsernameProfanityFilter.containsProfanity("putamadre"))
        #expect(UsernameProfanityFilter.containsProfanity("mierda"))
        #expect(UsernameProfanityFilter.containsProfanity("cabron"))
        #expect(UsernameProfanityFilter.containsProfanity("coño"))
    }

    @Test func blocksFrenchProfanity() {
        #expect(UsernameProfanityFilter.containsProfanity("putain"))
        #expect(UsernameProfanityFilter.containsProfanity("merde"))
        #expect(UsernameProfanityFilter.containsProfanity("connard"))
        #expect(UsernameProfanityFilter.containsProfanity("salope"))
    }

    @Test func validationFailureCases() {
        #expect(UsernameValidation.failure(for: "   ") == .empty)
        #expect(UsernameValidation.failure(for: "shit") == .profanity)
        #expect(UsernameValidation.failure(for: "GoodName") == nil)
        #expect(UsernameValidation.trimmed("  GoodName  ") == "GoodName")
    }
}

// FR-80 (F-36): client↔server username-format parity. These fixtures mirror
// `isValidUserNameFormat` in firestore.rules exactly — a change to either side
// must touch both, or a name the client accepts dies silently at the rules
// boundary (owner-found 2026-09-07: spaced usernames stuck in the local-first UI).
@MainActor
struct UsernameValidationFormatTests {
    @Test func acceptsServerValidNames() {
        for name in ["Road_Tripper.99", "Kid_v2", "abc", String(repeating: "a", count: 24), "123456"] {
            #expect(UsernameValidation.failure(for: name) == nil, "expected \(name) to be valid")
        }
    }

    @Test func rejectsSpacesAndNonASCII() {
        #expect(UsernameValidation.failure(for: "Kid v2") == .invalidCharacters)
        #expect(UsernameValidation.failure(for: "Émilie") == .invalidCharacters)
        #expect(UsernameValidation.failure(for: "name@here") == .invalidCharacters)
    }

    @Test func rejectsLengthOutOfBounds() {
        #expect(UsernameValidation.failure(for: "ab") == .tooShort)
        #expect(UsernameValidation.failure(for: String(repeating: "a", count: 25)) == .tooLong)
    }

    @Test func rejectsDigitRunsAndPhoneShapes() {
        // Server: bare digit runs of 7-24 and NANP shapes are rejected; a 6-digit
        // run is deliberately allowed on both sides.
        #expect(UsernameValidation.failure(for: "1234567") == .looksLikePhoneNumber)
        #expect(UsernameValidation.failure(for: "5551234567") == .looksLikePhoneNumber)
        #expect(UsernameValidation.failure(for: "555-123-4567") == .looksLikePhoneNumber)
        #expect(UsernameValidation.failure(for: "555.123.4567") == .looksLikePhoneNumber)
    }

    @Test func profanityStillRejectedAfterFormatChecks() {
        #expect(UsernameValidation.failure(for: "fucker99") == .profanity)
    }
}
