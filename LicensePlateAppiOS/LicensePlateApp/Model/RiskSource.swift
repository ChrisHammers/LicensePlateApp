//
//  RiskSource.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Origin of risk (local heuristics, sync replay, future server).
//

import Foundation

enum RiskSource: String, Codable, Sendable {
    case localHeuristic = "local_heuristic"
    case syncReplay = "sync_replay"
    case futureServerReview = "future_server_review"
}
