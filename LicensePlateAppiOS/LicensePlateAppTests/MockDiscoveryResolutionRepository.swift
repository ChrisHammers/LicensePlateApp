//
//  MockDiscoveryResolutionRepository.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockDiscoveryResolutionRepository: DiscoveryResolutionRepositoryProtocol {
    var resolutionsByItem: [String: [DiscoveryResolution]] = [:]
    var bySource: [String: DiscoveryResolution] = [:]

    func setModelContext(_ context: ModelContext) {}

    func save(_ resolution: DiscoveryResolution) throws {
        bySource[resolution.sourceEventId] = resolution
        var list = resolutionsByItem[resolution.itemId] ?? []
        list.append(resolution)
        resolutionsByItem[resolution.itemId] = list
    }

    func resolution(bySourceEventId sourceEventId: String) throws -> DiscoveryResolution? {
        bySource[sourceEventId]
    }

    func resolutions(sessionId: UUID, gameInstanceId: UUID, itemId: String) throws -> [DiscoveryResolution] {
        (resolutionsByItem[itemId] ?? []).filter { $0.sessionId == sessionId && $0.gameInstanceId == gameInstanceId }
    }
}
