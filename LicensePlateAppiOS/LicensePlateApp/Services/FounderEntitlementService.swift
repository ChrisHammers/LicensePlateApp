//
//  FounderEntitlementService.swift
//  LicensePlateApp
//
//  Grants the server-authoritative founder entitlement tag for eligible signed-in users.
//

import FirebaseFunctions
import Foundation

enum FounderEntitlementOutcome: Equatable {
    case granted
    case alreadyGranted
    case skipped(reason: String)
    case ineligible
    case failed
}

@MainActor
final class FounderEntitlementService {

    static let shared = FounderEntitlementService()

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func ensureIfPossible(isAnonymous: Bool) async -> FounderEntitlementOutcome {
        guard !isAnonymous else {
            AnalyticsService.shared.log(.founderEntitlementGrantSkipped(reason: "anonymous"))
            return .ineligible
        }

        do {
            let fn = functions.httpsCallable("ensureFounderEntitlementIfEligible")
            let result = try await fn.call(([:] as [String: Any]).addingClientMetadata())
            let outcome = parseOutcome(result.data)
            logAnalytics(for: outcome)
            return outcome
        } catch {
            #if DEBUG
            print("⚠️ ensureFounderEntitlementIfEligible failed: \(error.localizedDescription)")
            #endif
            return .failed
        }
    }

    private func parseOutcome(_ data: Any?) -> FounderEntitlementOutcome {
        guard let dict = data as? [String: Any],
              let outcome = dict["outcome"] as? String else {
            return .failed
        }

        switch outcome {
        case "granted":
            return .granted
        case "alreadyGranted":
            return .alreadyGranted
        case "skipped":
            let reason = (dict["reason"] as? String) ?? "unknown"
            return .skipped(reason: reason)
        case "ineligible":
            return .ineligible
        default:
            return .failed
        }
    }

    private func logAnalytics(for outcome: FounderEntitlementOutcome) {
        switch outcome {
        case .granted:
            AnalyticsService.shared.log(.founderEntitlementGranted)
        case .alreadyGranted:
            AnalyticsService.shared.log(.founderEntitlementGrantSkipped(reason: "already_granted"))
        case .skipped(let reason):
            AnalyticsService.shared.log(.founderEntitlementGrantSkipped(reason: reason))
        case .ineligible, .failed:
            break
        }
    }
}
