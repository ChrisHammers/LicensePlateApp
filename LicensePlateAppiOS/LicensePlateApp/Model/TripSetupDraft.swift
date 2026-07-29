//
//  TripSetupDraft.swift
//  LicensePlateApp
//
//  Snapshot from TripSetup passed to GameSetup for new-trip creation.
//

import Foundation

/// Immutable trip configuration collected on the first setup step.
struct TripSetupDraft: Sendable, Hashable {
    let tripName: String
    let selectedPassengerIds: Set<String>
    let startTripRightAway: Bool
    let skipVoiceConfirmation: Bool
    let holdToTalk: Bool
    let saveLocationWhenMarkingPlates: Bool
    let showMyLocationOnLargeMap: Bool
    let trackMyLocationDuringTrip: Bool
    let showMyActiveTripOnLargeMap: Bool
    let showMyActiveTripOnSmallMap: Bool
}

enum GameSetupContext: Sendable {
    case newTrip(TripSetupDraft)
    case addToExistingTrip(sessionId: UUID)
}

enum CombinedTripSetupError: LocalizedError {
    case noCountriesSelected
    case noGameTypesSelected
    case sessionNotFound
    case notTripCreator
    case tripTerminal
    case couldNotAddGame

    var errorDescription: String? {
        switch self {
        case .noCountriesSelected: return "Select at least one country.".localized
        case .noGameTypesSelected: return "Select at least one game.".localized
        case .sessionNotFound: return "Trip not found.".localized
        case .notTripCreator: return "Only the Driver can add a game.".localized
        case .tripTerminal: return "This trip can’t be changed anymore.".localized
        case .couldNotAddGame: return "Could not add game.".localized
        }
    }
}
