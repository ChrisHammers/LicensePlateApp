//
//  FamilySettingsViewModelTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct FamilySettingsViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    private func auth(userId: String) -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: userId, userName: userId, firebaseUID: userId)
        return auth
    }

    private func makeViewModel(
        viewerId: String,
        creatorId: String,
        extraMembers: [(String, FamilyMember.FamilyRole)] = []
    ) throws -> FamilySettingsViewModel {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "fam-1"
        let family = Family(familyId: familyId, name: "Hammers", creatorId: creatorId)
        context.insert(family)
        let creator = FamilyMember(familyId: familyId, userId: creatorId, role: .creator)
        context.insert(creator)
        for (userId, role) in extraMembers {
            context.insert(FamilyMember(familyId: familyId, userId: userId, role: role))
        }
        try context.save()

        let repo = FamilyRepository.shared
        repo.setModelContext(context)
        let vm = FamilySettingsViewModel(familyRepository: repo, authService: auth(userId: viewerId))
        vm.loadData(familyId: familyId)
        return vm
    }

    @Test func creatorCanRemoveOtherMembersButNotSelf() throws {
        let vm = try makeViewModel(
            viewerId: "creator",
            creatorId: "creator",
            extraMembers: [("scout", .scout)]
        )

        #expect(vm.isCreator)
        #expect(vm.canRemoveMembers)
        #expect(vm.canRemove(memberId: "scout"))
        #expect(!vm.canRemove(memberId: "creator"))
    }

    @Test func nonCreatorCannotRemoveMembers() throws {
        let vm = try makeViewModel(
            viewerId: "scout",
            creatorId: "creator",
            extraMembers: [("scout", .scout)]
        )

        #expect(!vm.isCreator)
        #expect(!vm.canRemoveMembers)
        #expect(!vm.canRemove(memberId: "creator"))
        #expect(!vm.canRemove(memberId: "scout"))

        vm.removeMember(memberId: "creator")
        #expect(vm.showErrorAlert)
        #expect(vm.errorMessage == "Only the family creator can remove members.".localized)
    }

    @Test func nonCreatorIsNotCreatorForLeaveVsDeleteGates() throws {
        let vm = try makeViewModel(
            viewerId: "scout",
            creatorId: "creator",
            extraMembers: [("scout", .scout)]
        )

        // Leave is available to non-creators in UI; Delete stays creator-only.
        #expect(!vm.isCreator)
        #expect(vm.members.contains(where: { $0.userId == "scout" }))
    }
}
