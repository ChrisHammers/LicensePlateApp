//
//  FamilyMemberRolePresentationTests.swift
//  LicensePlateAppTests
//
//  Family role display: creator and captain both show as Captain;
//  Creator badge follows family.creatorId.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct FamilyMemberRolePresentationTests {
    @Test func creatorRoleShowsCaptainWithCreatorBadgeWhenMatchingCreatorId() {
        let presentation = FamilyMemberRolePresentation.make(
            role: .creator,
            memberUserId: "founder",
            familyCreatorId: "founder"
        )

        #expect(presentation.roleText == "Captain".localized)
        #expect(presentation.showsCreatorBadge == true)
        #expect(presentation.accessibilityText.contains("Captain".localized))
        #expect(presentation.accessibilityText.contains("family.a11y.creator_badge".localized))
    }

    @Test func captainRoleShowsCaptainWithoutCreatorBadge() {
        let presentation = FamilyMemberRolePresentation.make(
            role: .captain,
            memberUserId: "other-captain",
            familyCreatorId: "founder"
        )

        #expect(presentation.roleText == "Captain".localized)
        #expect(presentation.showsCreatorBadge == false)
        #expect(presentation.accessibilityText == "Captain".localized)
    }

    @Test func creatorBadgeFollowsCreatorIdNotOnlyRole() {
        let mismatched = FamilyMemberRolePresentation.make(
            role: .creator,
            memberUserId: "stale-role-user",
            familyCreatorId: "actual-founder"
        )
        #expect(mismatched.showsCreatorBadge == false)

        let matchedCaptainRole = FamilyMemberRolePresentation.make(
            role: .captain,
            memberUserId: "actual-founder",
            familyCreatorId: "actual-founder"
        )
        #expect(matchedCaptainRole.showsCreatorBadge == true)
        #expect(matchedCaptainRole.roleText == "Captain".localized)
    }

    @Test func nonCaptainRolesKeepExistingDisplayNamesWithoutBadge() {
        let scout = FamilyMemberRolePresentation.make(
            role: .scout,
            memberUserId: "scout-1",
            familyCreatorId: "founder"
        )
        let sergeant = FamilyMemberRolePresentation.make(
            role: .sergeant,
            memberUserId: "sergeant-1",
            familyCreatorId: "founder"
        )
        let retired = FamilyMemberRolePresentation.make(
            role: .retiredGeneral,
            memberUserId: "retired-1",
            familyCreatorId: "founder"
        )

        #expect(scout.roleText == "Scout".localized)
        #expect(sergeant.roleText == "Sergeant".localized)
        #expect(retired.roleText == "Retired General".localized)
        #expect(scout.showsCreatorBadge == false)
        #expect(sergeant.showsCreatorBadge == false)
        #expect(retired.showsCreatorBadge == false)
    }

    @Test func missingCreatorIdFallsBackToCreatorRoleForBadge() {
        let presentation = FamilyMemberRolePresentation.make(
            role: .creator,
            memberUserId: "founder",
            familyCreatorId: nil
        )
        #expect(presentation.roleText == "Captain".localized)
        #expect(presentation.showsCreatorBadge == true)
    }
}
