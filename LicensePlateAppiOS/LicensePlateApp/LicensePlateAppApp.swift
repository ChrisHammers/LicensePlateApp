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
        // Initialize Firebase here (after delegate is fully set up)
        // This ensures Firebase's AppDelegateSwizzler can properly detect the delegate
        initializeFirebase()
        
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
        
        // Pre-render base tiles asynchronously (after boundaries are loaded)
        DispatchQueue.global(qos: .userInitiated).async {
            TileCacheService.shared.preRenderBaseTiles(for: PlateRegion.all) { progress in
                #if DEBUG
                if progress == 1.0 || Int(progress * 100) % 10 == 0 {
                    print("📊 Tile pre-rendering progress: \(Int(progress * 100))%")
                }
                #endif
            }
        }
        
        // Mark loading complete
        UserDefaults.standard.set(true, forKey: "boundariesLoaded")
        
        return true
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
}

@main
struct LicensePlateAppApp: App {
  
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  
    var sharedModelContainer: ModelContainer = {
        // Use versioned schema for future migration support
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            // Create ModelContainer with versioned schema and migration plan
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var authService = FirebaseAuthService()
    
    init() {
        // Firebase and Google Maps initialization moved to AppDelegate.application(_:didFinishLaunchingWithOptions:)
        // to ensure proper timing with delegate setup
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
        .modelContainer(sharedModelContainer)
    }
}
