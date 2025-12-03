//
//  GoogleMapsService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import GoogleMaps

/// Service for initializing and managing Google Maps
class GoogleMapsService {
    static let shared = GoogleMapsService()
    
    private var isInitialized = false
    
    private init() {}
    
    /// Initialize Google Maps with API key
    /// Call this in app startup (LicensePlateAppApp.init())
    func initialize(apiKey: String) {
        guard !isInitialized else {
            print("⚠️ Google Maps already initialized")
            return
        }
        
        GMSServices.provideAPIKey(apiKey)
        isInitialized = true
        print("✅ Google Maps initialized successfully")
    }
    
    /// Initialize Google Maps with API key from Info.plist
    /// Looks for "GoogleMapsAPIKey" in Info.plist
    func initializeFromPlist() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else {
            print("⚠️ Google Maps API key not found in Info.plist. Add 'GoogleMapsAPIKey' key.")
            return
        }
        
        initialize(apiKey: apiKey)
    }
    
    /// Initialize Google Maps with API key from environment-specific config
    /// Similar to Firebase initialization pattern
    func initializeFromConfig() {
        let configFileName: String
        #if DEBUG
        configFileName = "GoogleMaps-Info-Debug"
        #else
        configFileName = "GoogleMaps-Info-Release"
        #endif
        
        // Try multiple methods to find the config file
        var configPath: String?
        var config: NSDictionary?
        
        // Method 1: Try environment-specific file
        if let path = Bundle.main.path(forResource: configFileName, ofType: "plist") {
            configPath = path
            config = NSDictionary(contentsOfFile: path)
        }
        
        // Method 2: Try generic file
        if configPath == nil, let path = Bundle.main.path(forResource: "GoogleMaps-Info", ofType: "plist") {
            configPath = path
            config = NSDictionary(contentsOfFile: path)
        }
        
        // Method 3: Try using URLForResource (sometimes more reliable)
        if configPath == nil {
            if let url = Bundle.main.url(forResource: configFileName, withExtension: "plist") {
                configPath = url.path
                config = NSDictionary(contentsOf: url)
            }
        }
        
        if configPath == nil {
            if let url = Bundle.main.url(forResource: "GoogleMaps-Info", withExtension: "plist") {
                configPath = url.path
                config = NSDictionary(contentsOf: url)
            }
        }
        
        // Method 4: Fallback to Info.plist
        if configPath == nil {
            if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String {
                print("✅ Google Maps API key found in Info.plist")
                initialize(apiKey: apiKey)
                return
            }
        }
        
        // Extract API key from config (try both "APIKey" and "API_KEY" keys)
        guard let path = configPath,
              let dict = config else {
            print("⚠️ Google Maps configuration file not found. Tried:")
            print("   - \(configFileName).plist")
            print("   - GoogleMaps-Info.plist")
            print("   - Info.plist (GoogleMapsAPIKey key)")
            print("   App will work but maps may not display correctly.")
            print("   💡 Tip: Ensure the plist file is added to the target's 'Copy Bundle Resources' build phase.")
            return
        }
        
        // Try both key names (APIKey and API_KEY)
        let apiKey = (dict["APIKey"] as? String) ?? (dict["API_KEY"] as? String)
        
        guard let key = apiKey else {
            print("⚠️ Google Maps API key not found in config file: \(path)")
            print("   Expected key: 'APIKey' or 'API_KEY'")
            print("   App will work but maps may not display correctly.")
            return
        }
        
        print("✅ Google Maps configuration loaded from: \(path)")
        initialize(apiKey: key)
    }
}

