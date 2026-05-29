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
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        #endif
    }
}
