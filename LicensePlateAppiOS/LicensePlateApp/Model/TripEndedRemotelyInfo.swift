//
//  TripEndedRemotelyInfo.swift
//  LicensePlateApp
//
//  Payload when another participant ends the trip (remote `trip_ended`).
//

import Foundation

struct TripEndedRemotelyInfo: Equatable, Sendable {
    let sessionId: UUID
    let endedBy: String?
}
