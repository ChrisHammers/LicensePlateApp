//
//  AppUpdatePolicyEvaluator.swift
//  LicensePlateApp
//
//  Pure evaluation of `app_update_policy_v1` against the running client.
//

import Foundation

enum AppUpdateDecision: Equatable, Sendable {
    case none
    case soft(storeURL: URL?)
    case hard(storeURL: URL?)

    var isHard: Bool {
        if case .hard = self { return true }
        return false
    }

    var isSoft: Bool {
        if case .soft = self { return true }
        return false
    }

    var storeURL: URL? {
        switch self {
        case .none: return nil
        case .soft(let url), .hard(let url): return url
        }
    }

    var gateKind: String {
        switch self {
        case .none: return "none"
        case .soft: return "soft"
        case .hard: return "hard"
        }
    }
}

struct AppUpdateClientSnapshot: Equatable, Sendable {
    var marketingVersion: String
    var build: String
    var clientCompat: Int
    var osMajor: Int
    var osMinor: Int
    var osPatch: Int

    static func current(
        marketingVersion: String = ClientMetadata.current.clientAppVersion,
        build: String = ClientMetadata.current.clientAppBuild,
        clientCompat: Int = ClientCompat.current,
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> AppUpdateClientSnapshot {
        AppUpdateClientSnapshot(
            marketingVersion: marketingVersion,
            build: build,
            clientCompat: clientCompat,
            osMajor: osVersion.majorVersion,
            osMinor: osVersion.minorVersion,
            osPatch: osVersion.patchVersion
        )
    }
}

enum AppUpdatePolicyEvaluator {
    /// Evaluates a parsed policy. Pass `nil` for empty/invalid JSON (fail-open → `.none`).
    static func evaluate(
        policy: AppUpdatePolicy?,
        client: AppUpdateClientSnapshot
    ) -> AppUpdateDecision {
        guard let policy, let ios = policy.ios else {
            return .none
        }

        let storeURL = ios.storeUrl.flatMap { URL(string: $0) }
        let osCap = matchingOSCap(caps: ios.osCaps, client: client)

        if failsHard(floors: ios.hard, osCap: osCap, client: client) {
            return .hard(storeURL: storeURL)
        }
        if failsSoft(floors: ios.soft, osCap: osCap, client: client) {
            return .soft(storeURL: storeURL)
        }
        return .none
    }

    /// Convenience: parse JSON then evaluate. Empty/invalid → `.none`.
    static func evaluate(
        json: String,
        client: AppUpdateClientSnapshot
    ) -> AppUpdateDecision {
        evaluate(policy: AppUpdatePolicy.parse(json: json), client: client)
    }

    // MARK: - Floors

    private static func failsHard(
        floors: AppUpdatePolicy.VersionFloors?,
        osCap: AppUpdatePolicy.OSCap?,
        client: AppUpdateClientSnapshot
    ) -> Bool {
        guard let floors else { return false }

        if let minCompat = floors.minClientCompat, client.clientCompat < minCompat {
            return true
        }

        let effectiveVersion = clampedMarketingVersion(
            required: floors.minMarketingVersion,
            cap: osCap?.maxRequiredMarketingVersion
        )
        if let effectiveVersion,
           VersionCompare.compareMarketing(client.marketingVersion, effectiveVersion) == .orderedAscending {
            return true
        }

        let effectiveBuild = clampedBuild(
            required: floors.minBuild,
            cap: osCap?.maxRequiredBuild
        )
        if let effectiveBuild,
           VersionCompare.compareBuild(client.build, effectiveBuild) == .orderedAscending {
            return true
        }

        return false
    }

    private static func failsSoft(
        floors: AppUpdatePolicy.VersionFloors?,
        osCap: AppUpdatePolicy.OSCap?,
        client: AppUpdateClientSnapshot
    ) -> Bool {
        guard let floors else { return false }

        // Soft does not use minClientCompat; that is hard-only.
        let effectiveVersion = clampedMarketingVersion(
            required: floors.minMarketingVersion,
            cap: osCap?.maxRequiredMarketingVersion
        )
        if let effectiveVersion,
           VersionCompare.compareMarketing(client.marketingVersion, effectiveVersion) == .orderedAscending {
            return true
        }

        let effectiveBuild = clampedBuild(
            required: floors.minBuild,
            cap: osCap?.maxRequiredBuild
        )
        if let effectiveBuild,
           VersionCompare.compareBuild(client.build, effectiveBuild) == .orderedAscending {
            return true
        }

        return false
    }

    /// Cap never raises the floor; it only lowers an overly aggressive version requirement.
    private static func clampedMarketingVersion(required: String?, cap: String?) -> String? {
        guard let required else { return nil }
        guard let cap else { return required }
        if VersionCompare.compareMarketing(required, cap) == .orderedDescending {
            return cap
        }
        return required
    }

    private static func clampedBuild(required: Int?, cap: Int?) -> Int? {
        guard let required else { return nil }
        guard let cap else { return required }
        return min(required, cap)
    }

    private static func matchingOSCap(
        caps: [AppUpdatePolicy.OSCap],
        client: AppUpdateClientSnapshot
    ) -> AppUpdatePolicy.OSCap? {
        let clientOS = "\(client.osMajor).\(client.osMinor).\(client.osPatch)"
        // Prefer the tightest (lowest) exclusive ceiling that still applies.
        let matches = caps.filter { cap in
            VersionCompare.compareMarketing(clientOS, cap.maxOsVersionExclusive) == .orderedAscending
        }
        return matches.min { lhs, rhs in
            VersionCompare.compareMarketing(lhs.maxOsVersionExclusive, rhs.maxOsVersionExclusive) == .orderedAscending
        }
    }
}

// MARK: - Version compare helpers

enum VersionCompare {
    static func compareMarketing(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parseSemver(lhs)
        let right = parseSemver(rhs)
        if left.0 != right.0 { return left.0 < right.0 ? .orderedAscending : .orderedDescending }
        if left.1 != right.1 { return left.1 < right.1 ? .orderedAscending : .orderedDescending }
        if left.2 != right.2 { return left.2 < right.2 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    /// Compares client build string to required integer build.
    static func compareBuild(_ clientBuild: String, _ required: Int) -> ComparisonResult {
        let parsed = Int(clientBuild.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if parsed < required { return .orderedAscending }
        if parsed > required { return .orderedDescending }
        return .orderedSame
    }

    /// Soft-dismiss fingerprint from soft floors (before OS clamp — target the policy asks for).
    static func softFingerprint(floors: AppUpdatePolicy.VersionFloors?) -> String {
        let version = floors?.minMarketingVersion ?? ""
        let build = floors?.minBuild.map(String.init) ?? ""
        return "\(version)#\(build)"
    }

    private static func parseSemver(_ value: String) -> (Int, Int, Int) {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? value
        let parts = cleaned.split(separator: ".").prefix(3).compactMap { Int($0) }
        let major = parts.count > 0 ? parts[0] : 0
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0
        return (major, minor, patch)
    }
}
