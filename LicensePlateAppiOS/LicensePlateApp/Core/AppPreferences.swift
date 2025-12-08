//
//  AppPreferences.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import MapKit
import GoogleMaps

// MARK: - App Preferences Enums

enum AppDarkMode: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}

enum AppDistanceUnit: String, CaseIterable {
    case miles = "Miles"
    case kilometers = "Kilometers"
}

enum AppMapStyle: String, CaseIterable {
    case standard = "Standard"
    case satellite = "Satellite"
  #if DEBUG
    case custom = "Custom"
#endif
    
    /// Returns the MapStyle based on the preference (for MapKit compatibility)
    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard
        case .satellite:
            return .hybrid
        #if DEBUG
        case .custom:
            return .standard
        #endif
        }
    }
    
    /// Returns the GMSMapViewType for Google Maps
    var googleMapType: GMSMapViewType {
        switch self {
        case .standard:
            return .normal
        case .satellite:
            return .satellite
          #if DEBUG
        case .custom:
            return .normal // With custom styling
          #endif
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    
    /// Locale code for the language (e.g., "en", "es", "fr")
    var localeCode: String {
        switch self {
        case .english: return "en"
        case .spanish: return "es"
        case .french: return "fr"
        }
    }
    
    /// Initialize from locale code
    init?(localeCode: String) {
        let code = localeCode.lowercased()
        switch code {
        case "en", "english":
            self = .english
        case "es", "spanish", "español":
            self = .spanish
        case "fr", "french", "français":
            self = .french
        default:
            return nil
        }
    }
    
    /// Detect device language and return corresponding AppLanguage
    static func detectDeviceLanguage() -> AppLanguage {
        // Get preferred languages from device
        let preferredLanguages = Locale.preferredLanguages
        
        // Check each preferred language
        for languageCode in preferredLanguages {
            // Extract base language code (e.g., "es" from "es-MX")
            let baseLanguage = languageCode.components(separatedBy: "-").first?.lowercased() ?? languageCode.lowercased()
            
            // Map to AppLanguage
            if let appLanguage = AppLanguage(localeCode: baseLanguage) {
                return appLanguage
            }
        }
        
        // Default to English if no supported language found
        return .english
    }
}

enum AppTripSortOrder: String, CaseIterable {
    case dateCreated = "Date Created"
    case name = "Name"
    case progress = "Progress"
    case lastActive = "Last Active"
}

enum AppFontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

enum AppDefaultTab: String, CaseIterable {
    case trips = "Trips"
    case map = "Map"
    case stats = "Stats"
}

enum AppPlateDisplayFormat: String, CaseIterable {
    case fullName = "Full Name"
    case abbreviation = "Abbreviation"
}

enum AppMapDefaultZoom: String, CaseIterable {
    case close = "Close"
    case medium = "Medium"
    case far = "Far"
}

enum AppBackgroundStyle: String, CaseIterable {
    case none = "None"
    case paths = "Paths"
    case characters = "Characters"
}

enum AppMapProvider: String, CaseIterable {
    case apple = "Apple"
    case google = "Google"
}

// MARK: - App Preferences Utilities

struct AppPreferences {
    /// Get the MapStyle from the stored preference
    static func mapStyleFromPreference() -> MapStyle {
        let appMapStyleRaw = UserDefaults.standard.string(forKey: "appMapStyle") ?? AppMapStyle.standard.rawValue
        let mapStyle = AppMapStyle(rawValue: appMapStyleRaw) ?? .standard
        return mapStyle.mapStyle
    }
    
    /// Get the MapStyle from a raw string value (for use with @AppStorage)
    static func mapStyleFromPreference(rawValue: String) -> MapStyle {
        let mapStyle = AppMapStyle(rawValue: rawValue) ?? .standard
        return mapStyle.mapStyle
    }
    
    /// Get the ColorScheme from the stored preference
    static func colorSchemeFromPreference() -> ColorScheme? {
        let appDarkModeRaw = UserDefaults.standard.string(forKey: "appDarkMode") ?? AppDarkMode.system.rawValue
        return colorSchemeFromPreference(rawValue: appDarkModeRaw)
    }
    
    /// Get the ColorScheme from a raw string value (for use with @AppStorage)
    static func colorSchemeFromPreference(rawValue: String) -> ColorScheme? {
        let darkMode = AppDarkMode(rawValue: rawValue) ?? .system
        switch darkMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil // nil means use system setting
        }
    }
    
    /// Get the background image name based on style and color scheme
    static func backgroundImageName(style: AppBackgroundStyle, colorScheme: ColorScheme?) -> String? {
        // Determine if we're in dark mode
        let isDark: Bool
        if let colorScheme = colorScheme {
            isDark = colorScheme == .dark
        } else {
            // Use system color scheme
            isDark = UITraitCollection.current.userInterfaceStyle == .dark
        }
        
        switch style {
        case .none:
            return nil
        case .paths:
            return isDark ? "background_app_basic_dark" : "background_app_basic_light"
        case .characters:
            return isDark ? "background_app_cameo_dark" : "background_app_cameo_light"
        }
    }
    
    /// Get the default map provider (Google Maps)
    static func defaultMapProvider() -> AppMapProvider {
        return .google
    }
}

