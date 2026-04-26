//
//  ClientMetadata.swift
//  LicensePlateApp
//

import Foundation
import UIKit

struct ClientMetadata {
    let phoneModel: String
    let phoneModelIdentifier: String
    let phoneOSVersion: String
    let clientAppVersion: String
    let clientAppBuild: String

    static var current: ClientMetadata {
        let identifier = hardwareModelIdentifier()
        return ClientMetadata(
            phoneModel: marketingName(for: identifier),
            phoneModelIdentifier: identifier,
            phoneOSVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            clientAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            clientAppBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
    }

    var firestoreValue: [String: Any] {
        [
            "phoneModel": phoneModel,
            "phoneModelIdentifier": phoneModelIdentifier,
            "phoneOSVersion": phoneOSVersion,
            "clientAppVersion": clientAppVersion,
            "clientAppBuild": clientAppBuild
        ]
    }

    private static func hardwareModelIdentifier() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let simulatorIdentifier = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulatorIdentifier.isEmpty {
            return simulatorIdentifier
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        if (identifier == "arm64" || identifier == "x86_64"),
           let simulatorDeviceName = environment["SIMULATOR_DEVICE_NAME"],
           !simulatorDeviceName.isEmpty {
            return simulatorDeviceName
        }
        return identifier
    }

    private static func marketingName(for identifier: String) -> String {
        modelNameByIdentifier[identifier] ?? identifier
    }

    private static let modelNameByIdentifier: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",

        "iPad11,1": "iPad mini (5th generation)",
        "iPad11,2": "iPad mini (5th generation)",
        "iPad11,3": "iPad Air (3rd generation)",
        "iPad11,4": "iPad Air (3rd generation)",
        "iPad11,6": "iPad (8th generation)",
        "iPad11,7": "iPad (8th generation)",
        "iPad12,1": "iPad (9th generation)",
        "iPad12,2": "iPad (9th generation)",
        "iPad13,1": "iPad Air (4th generation)",
        "iPad13,2": "iPad Air (4th generation)",
        "iPad13,4": "iPad Pro 11-inch (3rd generation)",
        "iPad13,5": "iPad Pro 11-inch (3rd generation)",
        "iPad13,6": "iPad Pro 11-inch (3rd generation)",
        "iPad13,7": "iPad Pro 11-inch (3rd generation)",
        "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad13,18": "iPad (10th generation)",
        "iPad13,19": "iPad (10th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        "iPad16,8": "iPad Air 11-inch (M4)",
        "iPad16,9": "iPad Air 11-inch (M4)",
        "iPad16,10": "iPad Air 13-inch (M4)",
        "iPad16,11": "iPad Air 13-inch (M4)"
    ]
}

extension Dictionary where Key == String, Value == Any {
    mutating func addClientMetadata() {
        self["clientMetadata"] = ClientMetadata.current.firestoreValue
    }

    func addingClientMetadata() -> [String: Any] {
        var copy = self
        copy.addClientMetadata()
        return copy
    }
}
