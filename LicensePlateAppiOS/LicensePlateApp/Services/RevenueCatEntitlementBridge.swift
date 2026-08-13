//
//  RevenueCatEntitlementBridge.swift
//  LicensePlateApp
//
//  RevenueCat-friendly entitlement resolution: maps RC entitlements to UserTier and tags;
//  provides offerings, purchase, restore, and identify. Use protocol for testing.
//

import Foundation
import Combine
#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Protocol (app-level types only; no RevenueCat in interface)

/// Display model for a paywall package (store-agnostic).
struct PaywallPackage: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    let packageType: String?
}

/// Protocol for entitlement + paywall operations. Implement with RevenueCat or a mock for tests.
protocol RevenueCatEntitlementProviding: AnyObject {
    /// Current subscription tier from RevenueCat (or guest if not configured).
    var currentTier: UserTier { get }
    /// Tags such as "lifetime", "seasonal" from RevenueCat entitlements. Founder comes from Firestore.
    var currentTags: Set<String> { get }
    /// True if the user has an active entitlement at or above the given tier.
    func hasActiveEntitlement(for tier: UserTier) -> Bool
    /// Offerings for the paywall (packages to display). Empty if not configured or no offerings.
    var offerings: [PaywallPackage] { get }
    /// Load offerings from the backend. Call after configure/identify.
    func loadOfferings() async
    /// Purchase by package identifier. Returns true on success.
    func purchase(packageId: String) async -> Bool
    /// Restore purchases. Returns true if any entitlement was restored.
    func restore() async -> Bool
    /// Identify the current user (e.g. Firebase UID). Pass nil to use anonymous.
    func identify(userId: String?) async
    /// Whether the SDK is configured (API key present). If false, tier is guest and offerings empty.
    var isConfigured: Bool { get }
}

// MARK: - Bridge implementation (wraps RevenueCat)

/// Maps RevenueCat entitlement identifiers to UserTier and promotional tags.
/// Founder status is stored in Firestore `users/{uid}.entitlementTags`, not RevenueCat.
@MainActor
final class RevenueCatEntitlementBridge: ObservableObject, RevenueCatEntitlementProviding {

    static let shared = RevenueCatEntitlementBridge()

    private var cachedCustomerInfo: CustomerInfo?
    private var cachedOfferings: [PaywallPackage] = []
    private let apiKey: String?
    /// Whether `Purchases.configure` has actually run this launch (COPPA F-9, FR-46).
    private var hasConfiguredSDK = false

    var currentTier: UserTier {
        tierFromCache()
    }

    var currentTags: Set<String> {
        tagsFromCache()
    }

    var offerings: [PaywallPackage] {
        cachedOfferings
    }

    /// COPPA F-9 (FR-46): this now means "the SDK has actually been configured", not
    /// merely "an API key exists". Every `Purchases.shared` access below is guarded by
    /// it, and `Purchases.shared` traps when the SDK was never configured — so this is
    /// what makes deferring `configure()` past app launch safe.
    var isConfigured: Bool {
        hasConfiguredSDK
    }

    /// Whether a key exists at all. The FR-46 gate asks this before deciding whether
    /// starting RevenueCat is even possible for the resolved posture.
    var hasAPIKey: Bool {
        (apiKey ?? "").isEmpty == false
    }

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Self.readAPIKeyFromPlist()
    }

    /// Configure RevenueCat. No-op if the API key is missing or the SDK is already up.
    ///
    /// COPPA F-9 (FR-46): called by `DeferredSDKStartupService` on the first age-resolved
    /// posture that permits purchases — never from `didFinishLaunching`, because the SDK
    /// opens network connections as soon as it is configured.
    func configure() {
        guard !hasConfiguredSDK, let key = apiKey, !key.isEmpty else {
            return
        }
        #if canImport(RevenueCat)
        Purchases.configure(withAPIKey: key)
        #endif
        hasConfiguredSDK = true
    }

    func hasActiveEntitlement(for tier: UserTier) -> Bool {
        currentTier >= tier
    }

    func loadOfferings() async {
        #if canImport(RevenueCat)
        guard isConfigured else {
            cachedOfferings = []
            return
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            var packages: [PaywallPackage] = []
            if let current = offerings.current {
                for pkg in current.availablePackages {
                    packages.append(PaywallPackage(
                        id: pkg.identifier,
                        displayName: pkg.storeProduct.localizedTitle,
                        displayPrice: pkg.storeProduct.localizedPriceString,
                        packageType: String(describing: pkg.packageType)
                    ))
                }
            }
            cachedOfferings = packages
            await refreshCustomerInfo()
            objectWillChange.send()
        } catch {
            cachedOfferings = []
        }
        #else
        cachedOfferings = []
        #endif
    }

    func purchase(packageId: String) async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else { return false }
            guard let package = current.availablePackages.first(where: { $0.identifier == packageId }) else { return false }
            _ = try await Purchases.shared.purchase(package: package)
            await refreshCustomerInfo()
            objectWillChange.send()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func restore() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        do {
            _ = try await Purchases.shared.restorePurchases()
            await refreshCustomerInfo()
            objectWillChange.send()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func identify(userId: String?) async {
        #if canImport(RevenueCat)
        guard isConfigured else { return }
        if let uid = userId, !uid.isEmpty {
            _ = try? await Purchases.shared.logIn(uid)
        } else {
            _ = try? await Purchases.shared.logOut()
        }
        await refreshCustomerInfo()
        objectWillChange.send()
        #endif
    }

    /// Refresh cached customer info (tier/tags). Call after purchase/restore/identify.
    func refreshCustomerInfo() async {
        #if canImport(RevenueCat)
        guard isConfigured else {
            cachedCustomerInfo = nil
            return
        }
        do {
            cachedCustomerInfo = try await Purchases.shared.customerInfo()
            objectWillChange.send()
        } catch {
            cachedCustomerInfo = nil
        }
        #else
        cachedCustomerInfo = nil
        #endif
    }

    // MARK: - Private

    private static func readAPIKeyFromPlist() -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String, !key.isEmpty {
            return key
        }
        if let path = Bundle.main.path(forResource: "RevenueCat-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["RevenueCatAPIKey"] as? String, !key.isEmpty {
            return key
        }
        return nil
    }

    private func tierFromCache() -> UserTier {
        #if canImport(RevenueCat)
        guard let info = cachedCustomerInfo else { return .guest }
        let all = info.entitlements.all
        if all["royale"]?.isActive == true { return .royale }
        if all["gold"]?.isActive == true { return .gold }
        if all["premium"]?.isActive == true { return .gold }
        return .guest
        #else
        return .guest
        #endif
    }

    private func tagsFromCache() -> Set<String> {
        #if canImport(RevenueCat)
        var tags: Set<String> = []
        guard let info = cachedCustomerInfo else { return tags }
        for (id, ent) in info.entitlements.all where ent.isActive {
            let lower = id.lowercased()
            if ["lifetime", "achievement", "seasonal", "specialPromotion"].contains(lower) {
                tags.insert(lower)
            }
        }
        return tags
        #else
        return []
        #endif
    }
}

// MARK: - CustomerInfo placeholder when RevenueCat not imported

#if !canImport(RevenueCat)
private struct CustomerInfo {
    var entitlements: [String: EntitlementInfo] { [:] }
}
private struct EntitlementInfo {
    var isActive: Bool { false }
}
#endif
