//
//  ProgressionRewardsConfigProvider.swift
//  LicensePlateApp
//
//  Single injection point for progression rewards config (Phase 1 lite Step 2).
//

import Foundation

protocol ProgressionRewardsConfigProviding: Sendable {
    var current: ProgressionRewardsConfig { get }
    func refresh()
}

final class ProgressionRewardsConfigProvider: ProgressionRewardsConfigProviding, @unchecked Sendable {

    static let shared = ProgressionRewardsConfigProvider()

    private let lock = NSLock()
    private var cached: ProgressionRewardsConfig

    init(bundle: Bundle = .main) {
        cached = ProgressionRewardsConfigLoader.loadBundled(bundle: bundle)
    }

    var current: ProgressionRewardsConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Step 2: reload bundled JSON only. Step 3 merges Remote Config presentation overrides.
    func refresh() {
        let loaded = ProgressionRewardsConfigLoader.loadBundled()
        lock.lock()
        cached = loaded
        lock.unlock()
    }
}
