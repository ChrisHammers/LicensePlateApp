//
//  CrashReportingService.swift
//  LicensePlateApp
//
//  Step 18 — Thin Crashlytics wrapper so app code does not import Crashlytics directly.
//

import Foundation

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

@MainActor
final class CrashReportingService {
    static let shared = CrashReportingService()

    private init() {}

    /// Crashlytics collection needs no call of its own: linking the SDK plus
    /// `FirebaseApp.configure` enables it, and crash reporting is internal-ops, so it is
    /// permitted before age resolution (FR-46).
    ///
    /// COPPA F-16 (FR-58): this seam stays analytics-free. It used to log
    /// `crash_reporting_configured` from inside the launch path, which — on a relaunch
    /// after a resolved session, where the persisted collection switch is still ON —
    /// was an event collected before the holds were installed.
    func configure() {}

    func record(error: Error, context: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: error, userInfo: ["context": context])
        #endif
        AnalyticsService.shared.log(.crashReportingNonFatalRecorded(context: context))
    }
}
