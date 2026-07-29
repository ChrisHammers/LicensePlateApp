//
//  SessionBoundLocationSettings.swift
//  LicensePlateApp
//
//  LocationSettingsProviding backed by EffectiveSettingsResolver for one trip + viewer.
//

import Foundation
import Combine

@MainActor
final class SessionBoundLocationSettings: LocationSettingsProviding, ObservableObject {
    let sessionId: UUID
    let userId: String
    private let resolver: EffectiveSettingsResolver
    private var cancellable: AnyCancellable?

    init(
        sessionId: UUID,
        userId: String,
        resolver: EffectiveSettingsResolver = .shared
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.resolver = resolver
        cancellable = resolver.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private var resolved: EffectiveLocationSettings {
        resolver.resolve(sessionId: sessionId, userId: userId)
    }

    var saveLocationWhenMarkingPlates: Bool { resolved.saveLocationWhenMarkingPlates }
    var showMyLocationOnLargeMap: Bool { resolved.showMyLocationOnLargeMap }
    var trackMyLocationDuringTrips: Bool { resolved.trackMyLocationDuringTrips }
    var skipVoiceConfirmation: Bool { resolved.skipVoiceConfirmation }
}
