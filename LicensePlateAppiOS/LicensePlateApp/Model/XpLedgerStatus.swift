//
//  XpLedgerStatus.swift
//  LicensePlateApp
//

import Foundation

enum XpLedgerStatus: String, Codable, CaseIterable, Sendable {
    case provisional = "provisional"
    case final = "final"
    case voided = "voided"
}
