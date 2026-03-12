//
//  LicensePlateAppApp.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
                         
        // Initialize app language on first launch based on device language
        LocalizationHelper.initializeAppLanguageIfNeeded()

        // Reset boundariesLoaded to false on app launch to ensure splash screen shows
        UserDefaults.standard.set(false, forKey: "boundariesLoaded")
        
        // Initialize Firebase here (after delegate is fully set up)
        // This ensures Firebase's AppDelegateSwizzler can properly detect the delegate
        initializeFirebase()

        // RevenueCat: configure after Firebase so we can identify user later. No-op if RevenueCatAPIKey missing.
        RevenueCatEntitlementBridge.shared.configure()

        #if DEBUG
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
    
    private func initializeFirebase() {
        // Try to initialize Firebase, but don't crash if config is missing
        // Use environment-specific config files based on build configuration
        // The FIREBASE_CONFIG_FILE build setting documents which file should be used
        let configFileName: String
        #if DEBUG
        configFileName = "GoogleService-Info-Debug"
        #else
        configFileName = "GoogleService-Info-Release"
        #endif
        
        // Try environment-specific config first, then fallback to generic name
        var path = Bundle.main.path(forResource: configFileName, ofType: "plist")
        if path == nil {
            path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        }
        
        guard let configPath = path else {
            print("⚠️ Firebase configuration not found. App will work in offline-only mode.")
            print("   Expected: \(configFileName).plist or GoogleService-Info.plist")
            return
        }
        
        guard let options = FirebaseOptions(contentsOfFile: configPath) else {
            print("⚠️ Failed to load Firebase configuration. App will work in offline-only mode.")
            return
        }
        
        FirebaseApp.configure(options: options)
        print("✅ Firebase initialized successfully with config: \(configFileName).plist")
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
    
    init() {
        // Firebase and Google Maps initialization moved to AppDelegate.application(_:didFinishLaunchingWithOptions:)
        // to ensure proper timing with delegate setup
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
        }
        .modelContainer(sharedModelContainer)
    }
}
