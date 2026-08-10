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

    func configure() {
        AnalyticsService.shared.log(.crashReportingConfigured)
    }

    func record(error: Error, context: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: error, userInfo: ["context": context])
        #endif
        AnalyticsService.shared.log(.crashReportingNonFatalRecorded(context: context))
    }
}
