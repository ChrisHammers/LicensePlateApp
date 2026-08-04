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
        let selection = makeProviderFactory()
        AppCheck.setAppCheckProviderFactory(selection.factory)
        #if DEBUG
        print("[App Check] Provider factory: \(selection.name)")
        #endif
        #endif
    }

    /// Call once after `FirebaseApp.configure()` in debug builds.
    static func logDevelopmentSetupHintIfNeeded() {
        #if DEBUG
        #if canImport(FirebaseAppCheck)
        #if targetEnvironment(simulator)
        if let pinnedToken = ProcessInfo.processInfo.environment["AppCheckDebugToken"],
           !pinnedToken.isEmpty {
            print("[App Check] Using pinned debug token from AppCheckDebugToken environment variable.")
            return
        }

        print(
            """
            [App Check] Simulator uses the debug provider. Register the debug token or set AppCheckDebugToken.
            1. Run once and copy the console line: App Check debug token: '…'
            2. Firebase Console → App Check → your iOS app → Manage debug tokens → Add token
            3. (Recommended) Pin that token for all simulators: Xcode → Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables → AppCheckDebugToken = <token>
            Physical Debug devices use DeviceCheck (no debug-token registration).
            """
        )
        #endif
        #endif
        #endif
    }

    #if canImport(FirebaseAppCheck)
    private struct ProviderSelection {
        let factory: AppCheckProviderFactory
        let name: String
    }

    private static func makeProviderFactory() -> ProviderSelection {
        #if targetEnvironment(simulator)
        // Simulators have no DeviceCheck/App Attest; debug tokens must be registered in Console.
        return ProviderSelection(
            factory: AppCheckDebugProviderFactory(),
            name: "debug (Simulator)"
        )
        #elseif DEBUG
        // Physical-device Debug builds: DeviceCheck so callables work without registering a
        // per-install App Check debug token (missing/invalid debug JWTs → auth VALID, app INVALID).
        return ProviderSelection(
            factory: DeviceCheckProviderFactory(),
            name: "DeviceCheck (Debug device)"
        )
        #else
        if isAppStoreDistributionInstall {
            return ProviderSelection(
                factory: AppAttestProviderFactory(),
                name: "App Attest (TestFlight/App Store)"
            )
        }
        // Local Release device installs (Xcode) also use DeviceCheck — same footgun as Debug.
        return ProviderSelection(
            factory: DeviceCheckProviderFactory(),
            name: "DeviceCheck (local device install)"
        )
        #endif
    }

    /// True when installed from TestFlight or the App Store (store receipt on disk).
    private static var isAppStoreDistributionInstall: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
    #endif
}
