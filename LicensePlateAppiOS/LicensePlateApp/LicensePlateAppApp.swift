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
    // Firebase initialization is handled in LicensePlateAppApp.init()
    // to support environment-specific config files
    return true
  }
}

@main
struct LicensePlateAppApp: App {
  
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            AppUser.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var authService = FirebaseAuthService()
    
    init() {
        // Initialize Firebase if configured (optional - app works without it)
        initializeFirebase()
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
        .modelContainer(sharedModelContainer)
    }
}
