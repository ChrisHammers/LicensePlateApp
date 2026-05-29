//
//  FamilyMemberUserIdsRepository.swift
//  LicensePlateApp
//
//  SwiftData read: active family member user ids for lifetime stats classification.
//

import Foundation
import SwiftData

enum FamilyMemberUserIdsRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "error.family_lookup_no_context".localized
        }
    }
}

@MainActor
final class FamilyMemberUserIdsRepository {
    static let shared = FamilyMemberUserIdsRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    /// All `userId` values in the subject’s active family (from cached `FamilyMember` rows), or empty if none.
    func activeFamilyMemberUserIds(forAppUserId userId: String) throws -> Set<String> {
        guard let ctx = modelContext else { throw FamilyMemberUserIdsRepositoryError.noModelContext }
        let userDescriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.id == userId }
        )
        guard let user = try ctx.fetch(userDescriptor).first else { return [] }
        guard let familyId = user.activeFamilyId, !familyId.isEmpty else { return [] }

        let memberDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == familyId }
        )
        let members = try ctx.fetch(memberDescriptor)
        return Set(members.map(\.userId))
    }
}
