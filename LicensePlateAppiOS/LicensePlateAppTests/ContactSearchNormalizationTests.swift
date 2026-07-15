//
//  ContactSearchNormalizationTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ContactSearchNormalizationTests {
    @Test func emailLowerTrimsAndLowercases() {
        #expect(ContactSearchNormalization.emailLower("  John@Gmail.COM ") == "john@gmail.com")
        #expect(ContactSearchNormalization.emailLower("   ") == nil)
    }

    @Test func phoneE164USFormatsTenDigit() {
        #expect(ContactSearchNormalization.phoneE164US("(203) 555-1111") == "+12035551111")
        #expect(ContactSearchNormalization.phoneE164US("12035551111") == "+12035551111")
        #expect(ContactSearchNormalization.phoneE164US("+12035551111") == "+12035551111")
    }

    @Test func userNameLower() {
        #expect(ContactSearchNormalization.userNameLower(" RoadTrip ") == "roadtrip")
    }
}

@MainActor
struct AddFriendSearchEmptyStateTests {
    @Test func emptyStateRequiresCompletedEmptySearch() {
        let vm = AddFriendViewModel()
        vm.searchQuery = "zzz"
        vm.isSearching = false
        vm.hasCompletedSearch = true
        vm.searchResults = []
        vm.showError = false
        // Without auth configured, empty state is false (guest/unauthenticated)
        #expect(vm.showNoUsersFoundEmptyState == false)
    }
}
