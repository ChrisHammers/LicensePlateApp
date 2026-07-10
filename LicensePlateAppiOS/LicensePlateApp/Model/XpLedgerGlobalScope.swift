//
//  XpLedgerGlobalScope.swift
//  LicensePlateApp
//
//  Sentinel session/game ids for user-scoped ledger rows (return streak, etc.).
//

import Foundation

enum XpLedgerGlobalScope {
    static let sessionId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let gameInstanceId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
}
