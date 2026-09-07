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
    
    /// Generate a default username. Does NOT incorporate the device identifier.
    ///
    /// FR-80 (COPPA F-36, fresh-audit finding M-2): an IDFV-derived fragment inside a
    /// guest username is a stable, per-device fingerprint the player never chose to
    /// share, which is exactly the "username silently carries identity" pattern this
    /// FR requires new-account generation to stop doing. The suffix is now purely
    /// random. `deviceId` is unused and kept only so existing call sites are unchanged
    /// (`FirebaseAuthService` passes it in several places) — smallest correct diff.
    static func generateDefaultUsername(deviceId _: String) -> String {
        let suffix = randomAlphanumericSuffix(length: 8)
        let randomNum = Int.random(in: 1000...9999)
        return "User\(suffix)\(randomNum)"
    }

    /// Random (not device-derived) alphanumeric string for `generateDefaultUsername`.
    /// Charset matches the server-side username format policy (firestore.rules
    /// `isValidUserNameFormat`) so a freshly generated guest name always passes it.
    private static func randomAlphanumericSuffix(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

