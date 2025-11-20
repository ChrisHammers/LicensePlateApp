//
//  AppPreferences.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import MapKit

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
    
    /// Returns the MapStyle based on the preference
    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard
        case .satellite:
            return .hybrid
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
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
}

