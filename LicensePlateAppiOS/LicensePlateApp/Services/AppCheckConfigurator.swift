//
//  AppCheckConfigurator.swift
//  LicensePlateApp
//
//  Step 18 — Firebase App Check bootstrap. Must run before FirebaseApp.configure.
//

import Foundation

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum AppCheckConfigurator {
    static func configure() {
        #if canImport(FirebaseAppCheck)
        AppCheck.setAppCheckProviderFactory(makeProviderFactory().factory)
        #endif
    }

    #if canImport(FirebaseAppCheck)
    private struct ProviderSelection {
        let factory: AppCheckProviderFactory
        let name: String
    }

    private static func makeProviderFactory() -> ProviderSelection {
        #if DEBUG
        return ProviderSelection(
            factory: AppCheckDebugProviderFactory(),
            name: "debug (Debug build)"
        )
        #else
        #if targetEnvironment(simulator)
        return ProviderSelection(
            factory: AppCheckDebugProviderFactory(),
            name: "debug (Simulator)"
        )
        #else
        if isAppStoreDistributionInstall {
            return ProviderSelection(
                factory: AppAttestProviderFactory(),
                name: "App Attest (TestFlight/App Store)"
            )
        }
        return ProviderSelection(
            factory: AppCheckDebugProviderFactory(),
            name: "debug (local device install)"
        )
        #endif
        #endif
    }

    /// True when installed from TestFlight or the App Store (store receipt on disk).
    private static var isAppStoreDistributionInstall: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
    #endif
}
