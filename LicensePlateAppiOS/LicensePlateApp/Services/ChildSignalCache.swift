//
//  ChildSignalCache.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-19 cache half / FR-39 device ratchet): device-local persistence of the
//  child signal between launches. Two pieces:
//
//  - Per-uid cache of the last server-resolved `users/{uid}.isChildAccount` value.
//    Trust is ASYMMETRIC (FR-19): cached TRUE is applied immediately (TFCD stamped
//    before `MobileAds.start()`); cached FALSE — or no cache — is never sufficient
//    for ad display until this session's fresh `users/{uid}` read confirms not-child.
//  - Device ratchet: set the moment any uid on this device is known/declared child;
//    never cleared. While set, anonymous/signed-out sessions are TFCD-tagged and
//    ad-ineligible (FR-39). A resolved adult sign-in gets normal treatment for that
//    session; the ratchet persists for later anonymous sessions.
//
//  UserDefaults only — no SwiftData involvement (SRS §7.4, frozen schema).
//

import Foundation

enum ChildSignalCacheKeys {
    static let cachedIsChildByUserId = "childSignal.cachedIsChildByUserId"
    static let deviceRatchet = "childSignal.deviceEverHostedChild"
}

@MainActor
final class ChildSignalCache {
    static let shared = ChildSignalCache()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Per-uid cache (FR-19)

    /// Tri-state: nil = this device has never resolved the flag for `userId`.
    /// nil is NEVER treated as "not child" by any consumer.
    func cachedIsChildAccount(for userId: String) -> Bool? {
        guard !userId.isEmpty else { return nil }
        return cachedByUserId[userId]
    }

    /// Records a server-resolved value. Writing TRUE also engages the device ratchet.
    func setCachedIsChildAccount(_ isChild: Bool, for userId: String) {
        guard !userId.isEmpty else { return }
        var dict = cachedByUserId
        dict[userId] = isChild
        defaults.set(dict, forKey: ChildSignalCacheKeys.cachedIsChildByUserId)
        if isChild {
            engageDeviceRatchet()
        }
    }

    /// True when any uid this device has seen resolved child-true. Consumed by the
    /// pre-`MobileAds.start()` stamp, where no current uid exists yet.
    var hasAnyCachedChildTrue: Bool {
        cachedByUserId.values.contains(true)
    }

    private var cachedByUserId: [String: Bool] {
        (defaults.dictionary(forKey: ChildSignalCacheKeys.cachedIsChildByUserId) as? [String: Bool]) ?? [:]
    }

    // MARK: - Device ratchet (FR-39)

    var isDeviceRatcheted: Bool {
        defaults.bool(forKey: ChildSignalCacheKeys.deviceRatchet)
    }

    /// One-way: the ratchet is never cleared (protective; survives sign-out).
    func engageDeviceRatchet() {
        guard !isDeviceRatcheted else { return }
        defaults.set(true, forKey: ChildSignalCacheKeys.deviceRatchet)
    }
}
