//
//  DiscoveryRiskFlagger.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Applies risk flags to a discovery using context; keeps heuristics independent of persistence.
//

import Foundation

protocol DiscoveryRiskFlagging: Sendable {
    func applyRiskFlags(to discovery: GameDiscovery, using context: DiscoveryActionContext) -> GameDiscovery
}

struct DiscoveryRiskFlagger: DiscoveryRiskFlagging {
    private let heuristics: DiscoverySpamHeuristicsProtocol

    init(heuristics: DiscoverySpamHeuristicsProtocol = DiscoverySpamHeuristics()) {
        self.heuristics = heuristics
    }

    func applyRiskFlags(to discovery: GameDiscovery, using context: DiscoveryActionContext) -> GameDiscovery {
        let generatedFlags = heuristics.evaluate(context: context).map { flag in
            var updated = flag
            updated.discoveryId = discovery.id
            return updated
        }
        var updatedDiscovery = discovery
        updatedDiscovery.riskFlags = generatedFlags
        return updatedDiscovery
    }
}
