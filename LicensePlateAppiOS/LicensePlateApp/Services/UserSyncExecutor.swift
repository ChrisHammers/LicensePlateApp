//
//  UserSyncExecutor.swift
//  LicensePlateApp
//
//  Step 06.5 — Executes user profile sync from the queue.
//

import Foundation

@MainActor
protocol UserSyncExecutorProtocol: AnyObject {
    func performUserSync(userId: String) async throws
}

@MainActor
final class UserSyncExecutor: UserSyncExecutorProtocol {
    private let authService: FirebaseAuthService
    private let userRepository: UserRepository

    init(authService: FirebaseAuthService, userRepository: UserRepository) {
        self.authService = authService
        self.userRepository = userRepository
    }

    func performUserSync(userId: String) async throws {
        guard let user = try await userRepository.getUser(userId: userId) else { return }
        try await authService.saveUserDataToFirestore(user)
    }
}
