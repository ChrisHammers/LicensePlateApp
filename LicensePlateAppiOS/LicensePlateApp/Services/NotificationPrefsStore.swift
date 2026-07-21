//
//  NotificationPrefsStore.swift
//  LicensePlateApp
//
//  In-memory cache of Firestore notificationPrefs for eligibility + settings UI.
//

import Foundation
import Combine

/// Reads the latest known account notification prefs (never @AppStorage source of truth).
@MainActor
protocol NotificationPrefsReading: AnyObject {
    var prefs: UserRepository.NotificationPrefs { get }
}

@MainActor
final class NotificationPrefsStore: ObservableObject, NotificationPrefsReading {
    static let shared = NotificationPrefsStore()

    @Published private(set) var prefs: UserRepository.NotificationPrefs = .default
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let userRepository: UserRepository
    private var loadedUserId: String?

    init(userRepository: UserRepository = .shared) {
        self.userRepository = userRepository
    }

    func apply(_ prefs: UserRepository.NotificationPrefs) {
        self.prefs = prefs
    }

    /// Load from Firestore into the cache. Safe to call on app foreground / settings appear.
    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await userRepository.fetchNotificationPrefs(userId: userId)
            prefs = loaded
            loadedUserId = userId
        } catch {
            lastErrorMessage = error.localizedDescription
            // Keep last known / defaults when offline.
        }
    }

    /// Persist full prefs map and update cache.
    func save(userId: String, prefs: UserRepository.NotificationPrefs) async {
        guard !userId.isEmpty else { return }
        self.prefs = prefs
        loadedUserId = userId
        do {
            try await userRepository.updateNotificationPrefs(userId: userId, prefs: prefs)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
