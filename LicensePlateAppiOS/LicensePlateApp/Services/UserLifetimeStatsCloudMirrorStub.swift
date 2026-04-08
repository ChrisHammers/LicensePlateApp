//
//  UserLifetimeStatsCloudMirrorStub.swift
//  LicensePlateApp
//
//  Post-MVP: mirror `UserLifetimeStats` to Firestore with the same typed error policy as
//  `UserLifetimeStatsRepository` (no silent failures in the coordinator). Replace this stub
//  with a real `UserLifetimeStatsCloudMirror` service when product schedules cloud backup.
//

import Foundation

enum UserLifetimeStatsCloudMirrorStub {
    /// Reserved hook — intentionally does nothing.
    static func scheduleUploadIfNeeded(userId: String, stats: UserLifetimeStats) {
        _ = userId
        _ = stats
    }
}
