//
//  TripMode.swift
//  LicensePlateApp
//
//  Gameplay model foundation — trip participation mode.
//

import Foundation

/// How a trip/session is played: solo, shared collaborative, competitive, or combined games.
/// Extensible for future modes (e.g. challenge, time-limited).
enum TripMode: String, Codable, CaseIterable, Sendable {
    /// Single player; no other participants.
    case solo
    /// Shared trip; discoveries count for the group (collaborative credit).
    case collaborative
    /// Separate scores per participant (competitive credit).
    case competitive
    /// Multiple game types in one trip (e.g. license plates + another game).
    case combined
}
