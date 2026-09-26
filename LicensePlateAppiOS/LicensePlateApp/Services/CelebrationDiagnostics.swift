//
//  CelebrationDiagnostics.swift
//  LicensePlateApp
//
//  §3.1.1 item 15 (2026-09-18). Sibling of XpToastDiagnostics: standalone so the repository layer
//  (UserProgressionRepository / UserAchievementRemoteRepository) depends on a diagnostics utility,
//  not on the celebration service's file.
//

import Foundation
import os

/// DEBUG-only trace of the rank / achievement celebration's remote half: listener bind → snapshot
/// (cache vs server) → local baseline → remote absorb/seal → present. `[Celebration]` in the Xcode
/// console; `subsystem com.HammersTech.LicensePlateApp / category Celebration` in Console.app so a
/// device that is NOT attached to Xcode can still be read.
///
/// The `remote.absorb` / `remote.seal` lines carry a counterfactual — the banner and popups the
/// pre-item-15 build WOULD have queued from this snapshot (nothing in the delivery outbox, nothing
/// persisted) — so one device pass proves both the diagnosis and the fix.
enum CelebrationDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.HammersTech.LicensePlateApp", category: "Celebration")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        print("[Celebration] \(text)")
        #endif
    }

    static func shortUid(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return String(value.prefix(6))
    }
}
