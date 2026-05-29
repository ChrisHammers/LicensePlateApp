//
//  XpProjectionState.swift
//  LicensePlateApp
//
//  Batched projection output for a session/game slice (optional VM subscription).
//

import Foundation

struct XpProjectionState: Sendable, Equatable {
    var sessionId: UUID
    var gameInstanceId: UUID
    var viewerUserId: String
    var balance: XpBalanceProjection
    var discoveryByItemId: [String: DiscoveryUiProjection]
    var feedLines: [XpFeedProjection]
    var lastRecomputedAt: Date
}
