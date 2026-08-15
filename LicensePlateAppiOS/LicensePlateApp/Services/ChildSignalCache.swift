//
//  ChildSignalCache.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-19 cache half / FR-39 device ratchet): device-local persistence of the
//  child signal between launches. Two pieces:
//
//  - Per-uid cache of the last server-resolved `users/{uid}.isChildAccount` value,
//    with the PROVENANCE of that value alongside it (FR-75 amendment / OD-8).
//    Trust is ASYMMETRIC (FR-19): cached TRUE is applied immediately (TFCD stamped
//    before `MobileAds.start()`); cached FALSE — or no cache — is never sufficient
//    for ad display until this session's fresh `users/{uid}` read confirms not-child.
//    The one exception is the LOCATION capability (OD-8), which may trust a cached
//    SERVER-EXPLICIT false; see `ChildLocationTrustPolicy`.
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
    /// FR-75 amendment (OD-8): uids whose cached value came from a document that
    /// EXPLICITLY carried `isChildAccount`. Device-local UserDefaults, never synced
    /// and never written to Firestore — same store, same lifetime, as the value it
    /// qualifies, so the two can never be persisted apart.
    static let serverExplicitUserIds = "childSignal.serverExplicitUserIds"
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
    ///
    /// - Parameter isServerExplicit: whether the resolved document literally carried
    ///   `isChildAccount` (`UserRepository.ChildAccountResolution.isServerExplicit`).
    ///   Defaults to FALSE so an unstated provenance is never trusted: the OD-8
    ///   location branch demands an explicit `false`, and "we did not say" must read
    ///   the same as "the key was absent". Writing always RESTATES the provenance, so
    ///   a later unqualified write demotes a previously explicit entry rather than
    ///   leaving a stale claim behind.
    func setCachedIsChildAccount(_ isChild: Bool, for userId: String, isServerExplicit: Bool = false) {
        guard !userId.isEmpty else { return }
        var dict = cachedByUserId
        dict[userId] = isChild
        defaults.set(dict, forKey: ChildSignalCacheKeys.cachedIsChildByUserId)
        setServerExplicit(isServerExplicit, for: userId)
        if isChild {
            engageDeviceRatchet()
        }
    }

    /// FR-75 amendment (OD-8): did this uid's cached value come from a document that
    /// EXPLICITLY carried `isChildAccount`? False when unknown, legacy, or absent —
    /// the absence of evidence never counts as evidence of adulthood.
    func isCachedValueServerExplicit(for userId: String) -> Bool {
        guard !userId.isEmpty else { return false }
        return serverExplicitUserIds.contains(userId)
    }

    /// True when any uid this device has seen resolved child-true. Consumed by the
    /// pre-`MobileAds.start()` stamp, where no current uid exists yet.
    var hasAnyCachedChildTrue: Bool {
        cachedByUserId.values.contains(true)
    }

    private var cachedByUserId: [String: Bool] {
        (defaults.dictionary(forKey: ChildSignalCacheKeys.cachedIsChildByUserId) as? [String: Bool]) ?? [:]
    }

    private var serverExplicitUserIds: Set<String> {
        Set(defaults.stringArray(forKey: ChildSignalCacheKeys.serverExplicitUserIds) ?? [])
    }

    private func setServerExplicit(_ isServerExplicit: Bool, for userId: String) {
        var ids = serverExplicitUserIds
        let changed = isServerExplicit ? ids.insert(userId).inserted : (ids.remove(userId) != nil)
        guard changed else { return }
        defaults.set(Array(ids), forKey: ChildSignalCacheKeys.serverExplicitUserIds)
    }

    // MARK: - Device ratchet (FR-39)

    var isDeviceRatcheted: Bool {
        defaults.bool(forKey: ChildSignalCacheKeys.deviceRatchet)
    }

    /// Protective and effectively one-way: engaging is free, lifting is not. Sign-out,
    /// cache misses, and stale reads never clear it.
    func engageDeviceRatchet() {
        guard !isDeviceRatcheted else { return }
        defaults.set(true, forKey: ChildSignalCacheKeys.deviceRatchet)
    }

    /// COPPA F-8: the ONE path that lifts the ratchet — a manager-authorized CORRECTION
    /// (fresh server `isChildAccount == false` for a uid this device had declared)
    /// leaving no child lineage behind. Callers must have already cleared that uid's
    /// cache entry and declared-history entry, and must gate on
    /// `ChildDeviceCorrectionPolicy.liftsDeviceMarkers`. A REVOCATION never reaches
    /// here: the flag stays true, so the correction test never fires.
    func disengageDeviceRatchet() {
        guard isDeviceRatcheted else { return }
        defaults.set(false, forKey: ChildSignalCacheKeys.deviceRatchet)
    }

    /// Drops a single uid's cached value entirely — value AND provenance, so no stale
    /// entry can resurrect the lineage or outlive the value it qualified (used by the
    /// correction path).
    func clearCachedIsChildAccount(for userId: String) {
        guard !userId.isEmpty else { return }
        setServerExplicit(false, for: userId)
        var dict = cachedByUserId
        guard dict.removeValue(forKey: userId) != nil else { return }
        defaults.set(dict, forKey: ChildSignalCacheKeys.cachedIsChildByUserId)
    }
}
