//
//  RewardDeliveryOutbox.swift
//  LicensePlateApp
//
//  Durable per-user reward delivery acknowledgments so offline celebrations
//  survive kill/relaunch without double-playing historical rewards.
//

import Foundation

enum RewardDeliveryState: String, Codable, Sendable {
    case pending
    case presented
    case dismissed
    case clawedBack
}

struct RewardDeliveryRecord: Codable, Equatable, Sendable {
    var semanticId: String
    var state: RewardDeliveryState
    var updatedAt: Date
}

@MainActor
final class RewardDeliveryOutbox {

    static let shared = RewardDeliveryOutbox()

    private let defaults: UserDefaults
    private var cache: [String: [String: RewardDeliveryRecord]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(userId: String, semanticId: String) -> RewardDeliveryState? {
        load(userId: userId)[semanticId]?.state
    }

    func hasPresentedOrDismissed(userId: String, semanticId: String) -> Bool {
        switch state(userId: userId, semanticId: semanticId) {
        case .presented, .dismissed, .clawedBack: return true
        case .pending, .none: return false
        }
    }

    func mark(userId: String, semanticId: String, state: RewardDeliveryState) {
        var map = load(userId: userId)
        map[semanticId] = RewardDeliveryRecord(
            semanticId: semanticId,
            state: state,
            updatedAt: Date()
        )
        cache[userId] = map
        persist(userId: userId, map: map)
    }

    func reset(userId: String) {
        cache[userId] = [:]
        defaults.removeObject(forKey: storageKey(userId))
    }

    func resetAll() {
        cache.removeAll()
    }

    private func load(userId: String) -> [String: RewardDeliveryRecord] {
        if let cached = cache[userId] { return cached }
        guard let data = defaults.data(forKey: storageKey(userId)),
              let decoded = try? JSONDecoder().decode([String: RewardDeliveryRecord].self, from: data)
        else {
            cache[userId] = [:]
            return [:]
        }
        cache[userId] = decoded
        return decoded
    }

    private func persist(userId: String, map: [String: RewardDeliveryRecord]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey(userId))
    }

    private func storageKey(_ userId: String) -> String {
        "rewardDeliveryOutbox.v1.\(userId)"
    }
}
