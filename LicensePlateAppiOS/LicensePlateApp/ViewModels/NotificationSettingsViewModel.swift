//
//  NotificationSettingsViewModel.swift
//  LicensePlateApp
//
//  Account-level notification prefs UI state. Persists via UserRepository (Firestore).
//

import Foundation
import Combine

@MainActor
final class NotificationSettingsViewModel: ObservableObject {
    @Published var friend: Bool = true
    @Published var family: Bool = true
    @Published var tripInvite: Bool = true
    @Published var tripEnded: Bool = true
    @Published var plateFoundByOpponent: Bool = true
    @Published var plateFoundByCoPilots: Bool = true
    @Published var inactiveTripReminder: Bool = true
    @Published var returnStreakReminder: Bool = true
    @Published var promotionsAndNews: Bool = false

    @Published private(set) var isSyncing = false
    @Published private(set) var isLoaded = false

    private let store: NotificationPrefsStore
    private var userId: String?
    private var suppressPersist = false

    init(store: NotificationPrefsStore = .shared) {
        self.store = store
        applyFromStore()
    }

    var currentPrefs: UserRepository.NotificationPrefs {
        UserRepository.NotificationPrefs(
            friend: friend,
            family: family,
            tripInvite: tripInvite,
            tripEnded: tripEnded,
            plateFoundByOpponent: plateFoundByOpponent,
            plateFoundByCoPilots: plateFoundByCoPilots,
            inactiveTripReminder: inactiveTripReminder,
            returnStreakReminder: returnStreakReminder,
            promotionsAndNews: promotionsAndNews
        )
    }

    func configure(userId: String?) {
        self.userId = userId
    }

    func loadIfNeeded() async {
        guard let userId, !userId.isEmpty else { return }
        await store.load(userId: userId)
        suppressPersist = true
        applyFromStore()
        isLoaded = true
        await Task.yield()
        suppressPersist = false
    }

    /// Call from toggle `onChange` handlers.
    func persistFromUI() async {
        guard !suppressPersist, !isSyncing else { return }
        guard let userId, !userId.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        let prefs = currentPrefs
        await store.save(userId: userId, prefs: prefs)
        if prefs.returnStreakReminder == false {
            ReturnStreakReminderService.shared.cancelReminder(reason: "user_disabled")
        } else {
            await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: userId)
        }
    }

    private func applyFromStore() {
        let p = store.prefs
        friend = p.friend
        family = p.family
        tripInvite = p.tripInvite
        tripEnded = p.tripEnded
        plateFoundByOpponent = p.plateFoundByOpponent
        plateFoundByCoPilots = p.plateFoundByCoPilots
        inactiveTripReminder = p.inactiveTripReminder
        returnStreakReminder = p.returnStreakReminder
        promotionsAndNews = p.promotionsAndNews
    }
}
