//
//  FirstSessionState.swift
//  LicensePlateApp
//
//  UserDefaults-backed first-session timestamps and flags (no SwiftData).
//

import Foundation

enum FirstSessionFlowVariant: String {
    case quickSolo = "quick_solo"
    case legacy = "legacy"
}

@MainActor
protocol FirstSessionStateStoring: AnyObject {
    var onboardingStartedAt: Date? { get set }
    var quickTripStartedAt: Date? { get set }
    var hasLoggedFirstFind: Bool { get set }
    var deferredSetupStepsCompleted: Set<String> { get set }
    var deferredSetupPromptDismissedAt: Date? { get set }
    var activeFlowVariant: FirstSessionFlowVariant? { get set }
    var lastOnboardingStepId: String? { get set }
    func elapsedMs(since anchor: Date?) -> Int
}

enum FirstSessionStateKeys {
    static let onboardingStartedAt = "firstSessionOnboardingStartedAt"
    static let quickTripStartedAt = "firstSessionQuickTripStartedAt"
    static let hasLoggedFirstFind = "firstSessionHasLoggedFirstFind"
    static let deferredSetupStepsCompleted = "deferredSetupStepsCompleted"
    static let deferredSetupPromptDismissedAt = "deferredSetupPromptDismissedAt"
    static let activeFlowVariant = "firstSessionActiveFlowVariant"
    static let lastOnboardingStepId = "firstSessionLastOnboardingStepId"
}

@MainActor
final class FirstSessionState: FirstSessionStateStoring {
    static let shared = FirstSessionState()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingStartedAt: Date? {
        get {
            let interval = defaults.double(forKey: FirstSessionStateKeys.onboardingStartedAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: FirstSessionStateKeys.onboardingStartedAt)
            } else {
                defaults.removeObject(forKey: FirstSessionStateKeys.onboardingStartedAt)
            }
        }
    }

    var quickTripStartedAt: Date? {
        get {
            let interval = defaults.double(forKey: FirstSessionStateKeys.quickTripStartedAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: FirstSessionStateKeys.quickTripStartedAt)
            } else {
                defaults.removeObject(forKey: FirstSessionStateKeys.quickTripStartedAt)
            }
        }
    }

    var hasLoggedFirstFind: Bool {
        get { defaults.bool(forKey: FirstSessionStateKeys.hasLoggedFirstFind) }
        set { defaults.set(newValue, forKey: FirstSessionStateKeys.hasLoggedFirstFind) }
    }

    var deferredSetupStepsCompleted: Set<String> {
        get {
            Set(defaults.stringArray(forKey: FirstSessionStateKeys.deferredSetupStepsCompleted) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: FirstSessionStateKeys.deferredSetupStepsCompleted)
        }
    }

    var deferredSetupPromptDismissedAt: Date? {
        get {
            let interval = defaults.double(forKey: FirstSessionStateKeys.deferredSetupPromptDismissedAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: FirstSessionStateKeys.deferredSetupPromptDismissedAt)
            } else {
                defaults.removeObject(forKey: FirstSessionStateKeys.deferredSetupPromptDismissedAt)
            }
        }
    }

    var activeFlowVariant: FirstSessionFlowVariant? {
        get {
            guard let raw = defaults.string(forKey: FirstSessionStateKeys.activeFlowVariant) else { return nil }
            return FirstSessionFlowVariant(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: FirstSessionStateKeys.activeFlowVariant)
            } else {
                defaults.removeObject(forKey: FirstSessionStateKeys.activeFlowVariant)
            }
        }
    }

    var lastOnboardingStepId: String? {
        get { defaults.string(forKey: FirstSessionStateKeys.lastOnboardingStepId) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: FirstSessionStateKeys.lastOnboardingStepId)
            } else {
                defaults.removeObject(forKey: FirstSessionStateKeys.lastOnboardingStepId)
            }
        }
    }

    func elapsedMs(since anchor: Date?) -> Int {
        guard let anchor else { return 0 }
        return max(0, Int(Date().timeIntervalSince(anchor) * 1000))
    }
}
