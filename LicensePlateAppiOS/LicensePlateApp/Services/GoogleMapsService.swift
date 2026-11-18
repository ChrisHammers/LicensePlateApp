//
//  GoogleMapsService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import GoogleMaps

/// Starts the Google Maps SDK on demand. COPPA F-37 (FR-81(e)): never called at launch;
/// `MapProviderPolicy.resolvedProvider` calls `startIfNeeded()` only when a DEBUG build,
/// with the Map Provider switch on Google, in a confirmed-adult session, is about to
/// show a Google map. A release build never starts the SDK.
final class GoogleMapsService {
    static let shared = GoogleMapsService(
        loadAPIKey: GoogleMapsService.bundledDebugAPIKey,
        provideAPIKey: { GMSServices.provideAPIKey($0) }
    )

    private let loadAPIKey: () -> String?
    private let provideAPIKey: (String) -> Bool
    private var didAttemptStart = false
    private(set) var isStarted = false

    init(loadAPIKey: @escaping () -> String?, provideAPIKey: @escaping (String) -> Bool) {
        self.loadAPIKey = loadAPIKey
        self.provideAPIKey = provideAPIKey
    }

    /// Gives the SDK its key on the first call and returns whether it started. Later
    /// calls return the first result without touching the SDK (`provideAPIKey` may be
    /// called at most once per process). An empty or missing key never reaches the SDK.
    @discardableResult
    func startIfNeeded() -> Bool {
        #if DEBUG
        guard !didAttemptStart else { return isStarted }
        didAttemptStart = true
        guard let key = Self.usableKey(loadAPIKey()) else { return false }
        isStarted = provideAPIKey(key)
        return isStarted
        #else
        return false
        #endif
    }

    /// A key the SDK can use: non-empty after trimming whitespace.
    nonisolated static func usableKey(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The first usable `API_KEY` from the gitignored `GoogleMaps-Info-Debug.plist`,
    /// then `GoogleMaps-Info.plist`.
    nonisolated private static func bundledDebugAPIKey() -> String? {
        for name in ["GoogleMaps-Info-Debug", "GoogleMaps-Info"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "plist"),
               let dict = NSDictionary(contentsOf: url),
               let key = usableKey(dict["API_KEY"] as? String) {
                return key
            }
        }
        return nil
    }
}
