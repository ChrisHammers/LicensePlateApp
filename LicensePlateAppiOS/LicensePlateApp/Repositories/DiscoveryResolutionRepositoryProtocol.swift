//
//  DiscoveryResolutionRepositoryProtocol.swift
//  LicensePlateApp
//

import Foundation
import SwiftData

protocol DiscoveryResolutionRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    /// Insert or replace by `resolutionId`.
    func save(_ resolution: DiscoveryResolution) throws
    func resolution(bySourceEventId sourceEventId: String) throws -> DiscoveryResolution?
    func resolutions(sessionId: UUID, gameInstanceId: UUID, itemId: String) throws -> [DiscoveryResolution]
}
