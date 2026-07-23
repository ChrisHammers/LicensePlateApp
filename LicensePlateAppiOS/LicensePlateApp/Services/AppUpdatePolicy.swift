//
//  AppUpdatePolicy.swift
//  LicensePlateApp
//
//  Codable DTOs for Remote Config `app_update_policy_v1`.
//

import Foundation

struct AppUpdatePolicy: Equatable, Sendable {
    var schemaVersion: Int
    var ios: PlatformPolicy?

    struct PlatformPolicy: Equatable, Sendable {
        var storeUrl: String?
        var hard: VersionFloors?
        var soft: VersionFloors?
        var osCaps: [OSCap]
    }

    struct VersionFloors: Equatable, Sendable {
        var minClientCompat: Int?
        var minMarketingVersion: String?
        var minBuild: Int?
    }

    struct OSCap: Equatable, Sendable {
        /// Apply this cap when device OS is strictly less than this version.
        var maxOsVersionExclusive: String
        var maxRequiredMarketingVersion: String?
        var maxRequiredBuild: Int?
    }

    static func parse(json: String) -> AppUpdatePolicy? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(WireRoot.self, from: data).asPolicy()
        } catch {
            return nil
        }
    }
}

// MARK: - Wire decoding (tolerant of null / missing)

private struct WireRoot: Decodable {
    var schemaVersion: Int?
    var platforms: WirePlatforms?

    func asPolicy() -> AppUpdatePolicy {
        AppUpdatePolicy(
            schemaVersion: schemaVersion ?? 1,
            ios: platforms?.ios?.asPlatform()
        )
    }
}

private struct WirePlatforms: Decodable {
    var ios: WirePlatform?
}

private struct WirePlatform: Decodable {
    var storeUrl: String?
    var hard: WireFloors?
    var soft: WireFloors?
    var osCaps: [WireOSCap]?

    func asPlatform() -> AppUpdatePolicy.PlatformPolicy {
        AppUpdatePolicy.PlatformPolicy(
            storeUrl: storeUrl.flatMap { $0.isEmpty ? nil : $0 },
            hard: hard?.asFloors(),
            soft: soft?.asFloors(),
            osCaps: (osCaps ?? []).compactMap { $0.asCap() }
        )
    }
}

private struct WireFloors: Decodable {
    var minClientCompat: Int?
    var minMarketingVersion: String?
    var minBuild: Int?

    func asFloors() -> AppUpdatePolicy.VersionFloors {
        AppUpdatePolicy.VersionFloors(
            minClientCompat: minClientCompat,
            minMarketingVersion: minMarketingVersion.flatMap { $0.isEmpty ? nil : $0 },
            minBuild: minBuild
        )
    }
}

private struct WireOSCap: Decodable {
    var maxOsVersionExclusive: String?
    var maxRequiredMarketingVersion: String?
    var maxRequiredBuild: Int?

    func asCap() -> AppUpdatePolicy.OSCap? {
        guard let maxOs = maxOsVersionExclusive, !maxOs.isEmpty else { return nil }
        return AppUpdatePolicy.OSCap(
            maxOsVersionExclusive: maxOs,
            maxRequiredMarketingVersion: maxRequiredMarketingVersion.flatMap { $0.isEmpty ? nil : $0 },
            maxRequiredBuild: maxRequiredBuild
        )
    }
}
