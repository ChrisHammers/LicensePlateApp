//
//  AppUpdateGateService.swift
//  LicensePlateApp
//
//  Loads `app_update_policy_v1`, evaluates the running client, and drives
//  hard/soft update UX. Fail-open when JSON is empty or invalid.
//

import Foundation
import Combine
import UIKit

@MainActor
final class AppUpdateGateService: ObservableObject {
    static let shared = AppUpdateGateService()

    static let softDismissFingerprintKey = "app_update_soft_dismissed_fingerprint"

    @Published private(set) var decision: AppUpdateDecision = .none
    @Published private(set) var shouldPresentSoftPrompt = false

    /// Soft floors fingerprint from the last evaluated policy (for dismiss storage).
    private(set) var softFingerprint: String = "#"

    private let analytics: AnalyticsLogging
    private let openURL: (URL) -> Void
    private var softDismissStorage: SoftDismissStorage
    private var clientSnapshotProvider: () -> AppUpdateClientSnapshot
    private var hasLoggedHardShown = false
    private var hasLoggedSoftShown = false

    init(
        analytics: AnalyticsLogging,
        softDismissStorage: SoftDismissStorage,
        clientSnapshotProvider: @escaping () -> AppUpdateClientSnapshot,
        openURL: @escaping (URL) -> Void
    ) {
        self.analytics = analytics
        self.softDismissStorage = softDismissStorage
        self.clientSnapshotProvider = clientSnapshotProvider
        self.openURL = openURL
    }

    private convenience init() {
        self.init(
            analytics: AnalyticsService.shared,
            softDismissStorage: UserDefaultsSoftDismissStorage(
                key: AppUpdateGateService.softDismissFingerprintKey
            ),
            clientSnapshotProvider: { .current() },
            openURL: { UIApplication.shared.open($0) }
        )
    }

    func refresh(remoteConfig: RemoteConfigValueProviding) {
        refresh(json: remoteConfig.string(for: .appUpdatePolicyV1))
    }

    func refresh(json: String) {
        let client = clientSnapshotProvider()
        let policy = AppUpdatePolicy.parse(json: json)
        softFingerprint = VersionCompare.softFingerprint(floors: policy?.ios?.soft)
        let raw = AppUpdatePolicyEvaluator.evaluate(policy: policy, client: client)
        decision = raw

        switch raw {
        case .hard:
            shouldPresentSoftPrompt = false
            if !hasLoggedHardShown {
                hasLoggedHardShown = true
                analytics.log(
                    .forceUpdateGateShown(
                        gateKind: raw.gateKind,
                        clientCompat: client.clientCompat,
                        appVersion: client.marketingVersion,
                        appBuild: client.build
                    )
                )
            }
        case .soft:
            let dismissed = softDismissStorage.fingerprint == softFingerprint
            shouldPresentSoftPrompt = !dismissed
            if shouldPresentSoftPrompt, !hasLoggedSoftShown {
                hasLoggedSoftShown = true
                analytics.log(
                    .softUpdatePromptShown(
                        gateKind: raw.gateKind,
                        clientCompat: client.clientCompat,
                        appVersion: client.marketingVersion,
                        appBuild: client.build
                    )
                )
            }
        case .none:
            shouldPresentSoftPrompt = false
        }
    }

    func dismissSoft() {
        guard case .soft = decision else { return }
        softDismissStorage.fingerprint = softFingerprint
        shouldPresentSoftPrompt = false
        let client = clientSnapshotProvider()
        analytics.log(
            .softUpdatePromptDismissed(
                gateKind: "soft",
                clientCompat: client.clientCompat,
                appVersion: client.marketingVersion,
                appBuild: client.build
            )
        )
    }

    func openStore() {
        let client = clientSnapshotProvider()
        analytics.log(
            .updateStoreCTATapped(
                gateKind: decision.gateKind,
                clientCompat: client.clientCompat,
                appVersion: client.marketingVersion,
                appBuild: client.build
            )
        )
        guard let url = decision.storeURL else { return }
        openURL(url)
    }
}

// MARK: - Soft dismiss storage

protocol SoftDismissStorage: AnyObject {
    var fingerprint: String { get set }
}

final class UserDefaultsSoftDismissStorage: SoftDismissStorage {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "app_update_soft_dismissed_fingerprint"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var fingerprint: String {
        get { defaults.string(forKey: key) ?? "" }
        set { defaults.set(newValue, forKey: key) }
    }
}
