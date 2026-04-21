//
//  MainCoordinator.swift
//  LicensePlateApp
//
//  Step 6.8 — Coordinator for main tab trip/game navigation. Path drives NavigationStack; no NavigationLink in this flow.
//

import SwiftUI
import Combine
import FirebaseAuth

/// Coordinator for main (home) trip and game navigation. Owns path; open session/game via methods.
@MainActor
final class MainCoordinator: ObservableObject {

    /// Single path element: session screen or game screen.
    enum MainRoute: Hashable {
        case session(UUID)
        case game(sessionId: UUID, gameId: UUID)
    }

    @Published var path: [MainRoute] = []

    func openSession(_ sessionId: UUID) {
        path.append(.session(sessionId))
    }

    func openGame(sessionId: UUID, gameId: UUID) {
        path.append(.game(sessionId: sessionId, gameId: gameId))
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
        if path.isEmpty {
            let selfUid = Auth.auth().currentUser?.uid
            UserProfileListenCoordinator.shared.setPinnedUsers(selfUserId: selfUid, rosterUserIds: [])
        }
    }

    func popToRoot() {
        path.removeAll()
        let selfUid = Auth.auth().currentUser?.uid
        UserProfileListenCoordinator.shared.setPinnedUsers(selfUserId: selfUid, rosterUserIds: [])
    }
}
