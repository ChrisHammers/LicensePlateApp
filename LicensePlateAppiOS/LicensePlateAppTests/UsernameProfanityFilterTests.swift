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
