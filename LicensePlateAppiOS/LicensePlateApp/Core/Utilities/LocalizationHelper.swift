//
//  LocalizationHelper.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 12/04/25.
//

import Foundation

extension String {
    /// Localized string using iOS native localization system
    /// iOS automatically uses the device language or the language set in the app's .lproj folders
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    /// Localized string with format arguments
    func localized(_ arguments: CVarArg...) -> String {
        return String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

struct LocalizationHelper {
    /// Get the current app language from UserDefaults
    static var currentAppLanguage: AppLanguage {
        let appLanguageRaw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        return AppLanguage(rawValue: appLanguageRaw) ?? .english
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
    
    /// Initialize app language on first launch based on device language
    static func initializeAppLanguageIfNeeded() {
        // Check if language preference has been set
        if UserDefaults.standard.string(forKey: "appLanguage") == nil {
            // First launch - detect and set device language
            let detectedLanguage = detectDeviceLanguage()
            UserDefaults.standard.set(detectedLanguage.rawValue, forKey: "appLanguage")
            print("🌐 Detected device language: \(detectedLanguage.rawValue) (locale: \(detectedLanguage.localeCode))")
        }
    }
}

