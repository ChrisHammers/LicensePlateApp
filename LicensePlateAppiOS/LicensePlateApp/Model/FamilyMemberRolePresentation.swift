//
//  FamilyMemberRolePresentation.swift
//  LicensePlateApp
//
//  Non-persisted family role display: creators and captains both show as Captain;
//  the family founder is distinguished with a Creator badge via creatorId.
//

import Foundation

struct FamilyMemberRolePresentation: Equatable {
    let roleText: String
    let showsCreatorBadge: Bool

    var accessibilityText: String {
        if showsCreatorBadge {
            return "\(roleText), \("family.a11y.creator_badge".localized)"
        }
        return roleText
    }

    static func make(
        role: FamilyMember.FamilyRole,
        memberUserId: String,
        familyCreatorId: String?
    ) -> FamilyMemberRolePresentation {
        let roleText: String
        switch role {
        case .creator, .captain:
            roleText = "Captain".localized
        case .sergeant, .scout, .retiredGeneral:
            roleText = role.displayName
        }

        let showsCreatorBadge: Bool
        if let familyCreatorId {
            showsCreatorBadge = memberUserId == familyCreatorId
        } else {
            showsCreatorBadge = role == .creator
        }

        return FamilyMemberRolePresentation(
            roleText: roleText,
            showsCreatorBadge: showsCreatorBadge
        )
    }
}
