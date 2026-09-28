//
//  GameplaySyncDiagnostics.swift
//  LicensePlateApp
//
//  §3.1.1 item 22 — DEBUG-only trace of the gameplay UPLOAD path: a find is recorded and
//  queued → a flush is triggered (or skipped, and why) → each queue row gets a server
//  verdict or a classified failure. Every line is prefixed `[GameplaySync]` in the Xcode
//  console and carried as `subsystem com.HammersTech.LicensePlateApp / category GameplaySync`
//  in Console.app so a device that is NOT attached to Xcode can still be read.
//
//  Why it exists: a device whose finds never reached the server used to print NOTHING.
//  Every branch on this path — the offline skip, a suspended queue, a coalesced flush, a
//  hung callable, a transient failure parked for up to an hour, a permanent rejection — was
//  silent or analytics-only, and the owner was left looking at a second device with
//  "280 unsynced XP" and no line saying why.
//
//  Event ids and session ids are shortened to 8 characters; uids never appear.
//

import Foundation
import os

enum GameplaySyncDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.HammersTech.LicensePlateApp", category: "GameplaySync")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        print("[GameplaySync] \(text)")
        #endif
    }

    /// First 8 characters, matching the `[TripEndSync]` convention.
    static func short(_ id: String) -> String {
        String(id.prefix(8))
    }

    static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    /// A server or SDK message, flattened and trimmed so one verdict stays on one line.
    static func message(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription.replacingOccurrences(of: "\n", with: " ")
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }
}
