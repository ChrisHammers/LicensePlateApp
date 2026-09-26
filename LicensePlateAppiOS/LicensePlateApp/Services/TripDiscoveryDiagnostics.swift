//
//  TripDiscoveryDiagnostics.swift
//  LicensePlateApp
//
//  §3.1.1 item 19 — DEBUG-only trace of the account-scoped trip discovery channel:
//  gate → bind → snapshot → plan → import → retry. Every line is prefixed
//  `[TripDiscovery]` in the Xcode console and carried as
//  `subsystem com.HammersTech.LicensePlateApp / category TripDiscovery` in Console.app so a
//  device that is NOT attached to Xcode can still be read.
//
//  Its own category (not `TripEndSync`) so the owner can grep a restore without wading
//  through per-session listener chatter; the proof line that a restore WORKED still comes
//  from `[TripEndSync] re-assert: … localLive=[…] eligible=[…]` going non-empty on the
//  second device.
//
//  Uids are shortened to 6 characters and never logged in full.
//

import Foundation
import os

enum TripDiscoveryDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.HammersTech.LicensePlateApp", category: "TripDiscovery")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        print("[TripDiscovery] \(text)")
        #endif
    }

    /// First 6 characters only — enough to correlate two devices in one trace, never the uid.
    static func shortUid(_ userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return "nil" }
        return String(userId.prefix(6))
    }

    /// First 8 characters of a session UUID, matching the `[TripEndSync]` convention.
    static func shortSessionId(_ sessionId: UUID) -> String {
        String(sessionId.uuidString.prefix(8))
    }

    static func shortSessionIds(_ sessionIds: [UUID]) -> String {
        "[" + sessionIds.map { shortSessionId($0) }.joined(separator: ",") + "]"
    }
}
