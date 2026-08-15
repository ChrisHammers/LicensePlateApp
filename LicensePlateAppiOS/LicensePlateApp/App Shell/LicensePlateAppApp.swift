//
//  LicensePlateAppApp.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import UserNotifications
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
                         
        // Initialize app language on first launch based on device language
        LocalizationHelper.initializeAppLanguageIfNeeded()

        NewTripDefaultsBootstrap.registerFactoryDefaults()
        LocationSettingsBootstrap.registerFactoryDefaults()

        // Reset boundariesLoaded to false on app launch to ensure splash screen shows
        UserDefaults.standard.set(false, forKey: "boundariesLoaded")
        
        // Initialize Firebase here (after delegate is fully set up)
        // This ensures Firebase's AppDelegateSwizzler can properly detect the delegate.
        // `initializeFirebase()` brings up Firebase core, App Check and Crashlytics
        // (internal-ops, which FR-46 permits) and nothing else.
        let firebaseConfigured = initializeFirebase()

        // COPPA F-9/F-15/F-16 (FR-46/FR-56/FR-58): RevenueCat (`configure`/`identify`),
        // FCM registration, Firebase Analytics COLLECTION and `MobileAds.start()` are
        // deliberately NOT started here — this runs long before the session's age is
        // resolved. The gate installs their fail-closed holds now and releases them, with
        // the right posture, from the one apply-postures routine in
        // `ChildSessionPostureCoordinator`.
        //
        // FR-58: this is the FIRST thing after `FirebaseApp.configure`. Both Firebase
        // switches persist in UserDefaults, so on a relaunch after a resolved session
        // collection is ON until this line re-applies the hold — nothing may run in
        // between that could log.
        DeferredSDKStartupService.shared.installAtLaunch(isFirebaseConfigured: firebaseConfigured)

        // COPPA F-31 (FR-75b): apply the session's postures SYNCHRONOUSLY, here, from the
        // signals that are already readable — `ChildSignalCache`, `AgeGateStore`, and the
        // auth identity Firebase restored during `configure`. The other three triggers are
        // all asynchronous: the earliest of them runs behind `RootView`'s remote-config
        // fetch and `initializeAuthState`, and until it lands a device that already knows
        // it hosts a child still had factory-default `true` location flags plus a live OS
        // authorization from a previous grant — long enough to capture route points and
        // stamp coordinates onto discoveries. Nothing that can start location exists yet at
        // this line, so the window closes. Restrictive steps only: this pass deliberately
        // does not release the deferred SDK startups installed on the line above
        // (`Trigger.releasesDeferredSDKStartups`), so FR-46/FR-58 timing is unchanged.
        ChildSessionPostureCoordinator.shared.applyPostures(trigger: .launch)

        if firebaseConfigured {
            startPostConfigureFirebaseWork()
        }

        UNUserNotificationCenter.current().delegate = self

        // Cold start from a remote notification payload (tap may also arrive via didReceive).
        if let remoteUserInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                DeepLinkHandler.shared.applyNotificationUserInfo(remoteUserInfo)
            }
        }

        #if false
        // Initialize Google Maps after Firebase
        GoogleMapsService.shared.initializeFromConfig()
        
        // Pre-load boundaries synchronously to avoid delay when first opening map
        let startTime = Date()
        _ = RegionBoundaries.geoJSONBoundaries // Trigger lazy initialization
        let loadTime = Date().timeIntervalSince(startTime)
        print("✅ Pre-loaded boundaries in \(String(format: "%.2f", loadTime))s")
        
        // Pre-load polygon paths asynchronously (Option 1 + Option 3)
        DispatchQueue.main.async {
            PolygonPathCache.shared.preloadPaths(for: PlateRegion.all)
        }
        
        // Check if app version changed (indicating an update with potentially new GeoJSON files)
        // Only check and clear cache in DEBUG builds
        checkAndClearTileCacheIfNeeded()
        
        // Pre-render base tiles asynchronously (DEBUG only)
        DispatchQueue.global(qos: .userInitiated).async {
            TileCacheService.shared.preRenderBaseTiles(for: PlateRegion.all) { progress in
                if progress == 1.0 || Int(progress * 100) % 10 == 0 {
                    print("📊 Tile pre-rendering progress: \(Int(progress * 100))%")
                }
            }
        }
        #endif
        
        // DO NOT set boundariesLoaded here - let ContentView handle it after splash screen renders
        
        return true
    }
    
    /// Check if app version changed and clear tile cache if needed
    /// This ensures tiles are regenerated when GeoJSON files are updated in a new app version
    private func checkAndClearTileCacheIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ??
                             Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1.0.0"
        let lastVersion = UserDefaults.standard.string(forKey: "lastAppVersionForTileCache")
        
        if lastVersion != currentVersion {
            if let lastVersion = lastVersion {
                print("🔄 App version changed from \(lastVersion) to \(currentVersion)")
            } else {
                print("🔄 First launch or version tracking initialized: \(currentVersion)")
            }
            print("   Clearing tile cache to regenerate with updated boundaries if needed")
            TileCacheService.shared.clearCache()
            UserDefaults.standard.set(currentVersion, forKey: "lastAppVersionForTileCache")
        }
    }
    
    private func initializeFirebase() -> Bool {
        // Try to initialize Firebase, but don't crash if config is missing.
        // Release: GoogleService-Info-Release only (validated at build time; see CONFIG_SETUP.md).
        // Debug: GoogleService-Info-Debug, with fallback to GoogleService-Info.plist.
        let configFileName = FirebaseBuildConfiguration.expectedPlistBaseName

        var path = Bundle.main.path(forResource: configFileName, ofType: "plist")
        #if DEBUG
        if path == nil {
            path = Bundle.main.path(
                forResource: FirebaseBuildConfiguration.genericPlistBaseName,
                ofType: "plist"
            )
        }
        #endif

        guard let configPath = path else {
            print("⚠️ Firebase configuration not found. App will work in offline-only mode.")
            #if DEBUG
            print("   Expected: \(configFileName).plist or \(FirebaseBuildConfiguration.genericPlistBaseName).plist")
            #else
            print("   Expected: \(configFileName).plist")
            #endif
            return false
        }
        
        guard let options = FirebaseOptions(contentsOfFile: configPath) else {
            print("⚠️ Failed to load Firebase configuration. App will work in offline-only mode.")
            return false
        }
        
        AppCheckConfigurator.configure()
        FirebaseApp.configure(options: options)
        print("✅ Firebase initialized successfully with config: \(configFileName).plist")
        return true
    }

    /// COPPA F-16 (FR-58): everything that runs AFTER `FirebaseApp.configure` lives here
    /// instead of inside `initializeFirebase()`, so the caller can install the
    /// deferred-startup holds in between. Nothing in this function may log analytics
    /// synchronously; `RemoteConfigService.fetchAndActivate` (which does, and which the
    /// force-update gate needs at launch) is an internal operation kicked off as a Task
    /// after the holds are already in place.
    private func startPostConfigureFirebaseWork() {
        AppCheckConfigurator.logDevelopmentSetupHintIfNeeded()
        AppCheckReadiness.warmUp()
        CrashReportingService.shared.configure()
        Task { @MainActor in
            await RemoteConfigService.shared.fetchAndActivate()
        }
    }

    // Handle deep links
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        Task { @MainActor in
            DeepLinkHandler.shared.destination = DeepLinkHandler.shared.handleURL(url)
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            FirebaseMessagingService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CrashReportingService.shared.record(error: error, context: "apns_register_failed")
        #if DEBUG
        print("[Push] APNs registration failed: \(error.localizedDescription)")
        #endif
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show banners while foregrounded so invite pushes remain tappable.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Notification tap → same invite sheets as URL deep links.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            DeepLinkHandler.shared.applyNotificationUserInfo(userInfo)
            completionHandler()
        }
    }
}

@main
struct LicensePlateAppApp: App {
  
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    // Use versioned schema for future migration support
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isPreview
        )

        do {
            // Create ModelContainer with versioned schema and migration plan
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            let nsError = error as NSError
            var detail = "\(error)"
            if !nsError.userInfo.isEmpty {
                detail += " UserInfo: \(nsError.userInfo)"
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                detail += " Underlying: \(underlying.localizedDescription)"
                if !underlying.userInfo.isEmpty {
                    detail += " \(underlying.userInfo)"
                }
            }
            fatalError("Could not create ModelContainer: \(detail)")
        }
    }()
    
    @StateObject private var authService = FirebaseAuthService()
    @StateObject private var riskAssessmentService = RiskAssessmentService(analytics: AnalyticsService.shared)

    init() {
        // Firebase and Google Maps initialization moved to AppDelegate.application(_:didFinishLaunchingWithOptions:)
        // to ensure proper timing with delegate setup
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(riskAssessmentService)
                .onAppear {
                    RewardPopupWindowHost.shared.install(presenter: RewardPresenter.shared)
                    XpGainToastWindowHost.shared.install(service: XpGainToastService.shared)
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        if let dest = DeepLinkHandler.shared.handleURL(url) {
                            DeepLinkHandler.shared.destination = dest
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
