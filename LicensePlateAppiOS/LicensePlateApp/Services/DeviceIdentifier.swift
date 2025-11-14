//
//  DeviceIdentifier.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import UIKit

/// Helper for generating device-based identifiers
struct DeviceIdentifier {
    /// Get a unique device identifier tied to the app installation
    /// Uses identifierForVendor which is tied to the app and device
    static func getDeviceIdentifier() -> String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return identifier
        }
        // Fallback to a stored identifier in UserDefaults
        let key = "com.HammersTech.LicensePlateApp.deviceIdentifier"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let newIdentifier = UUID().uuidString
        UserDefaults.standard.set(newIdentifier, forKey: key)
        return newIdentifier
    }
    
    /// Generate a default username based on device identifier
    static func generateDefaultUsername(deviceId: String) -> String {
        // Use last 8 characters of device ID + random number for uniqueness
        let suffix = String(deviceId.suffix(8))
        let randomNum = Int.random(in: 1000...9999)
        return "User\(suffix)\(randomNum)"
    }
}

