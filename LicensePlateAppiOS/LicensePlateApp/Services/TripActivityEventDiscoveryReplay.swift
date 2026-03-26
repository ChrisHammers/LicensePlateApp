//
//  TripActivityEventDiscoveryReplay.swift
//  LicensePlateApp
//
//  Step 10 — Pure replay of region_found / region_removed into active discoveries per (gameInstanceId, regionId).
//  Multi-finder: multiple region_found for the same target append; region_removed with removedDiscoveryEventId removes one find.
//  Legacy region_removed (no removedDiscoveryEventId) clears all finds for that (game, region).
//

import Foundation

enum TripActivityEventDiscoveryReplay {

    /// Replays discovery-related events in chronological order.
    /// - Parameters:
    ///   - events: Session events sorted ascending by `timestamp` (caller responsibility).
    ///   - gameInstanceFilter: When non-nil, only events for that game instance are applied.
    /// - Returns: Flattened discoveries and one `FoundRegion` per target that still has at least one active discovery.
    static func replay(
        events: [TripActivityEvent],
        gameInstanceFilter: UUID?
    ) -> (discoveries: [GameDiscovery], foundRegions: [FoundRegion]) {
        let discoveryEvents = events.filter { $0.kind == .regionFound || $0.kind == .regionRemoved }
        var buckets: [String: [GameDiscovery]] = [:]

        for event in discoveryEvents {
            let payload = event.payload ?? [:]
            guard let regionId = payload[TripActivityEventPayloadKey.regionId], !regionId.isEmpty else { continue }
            guard let gameInstanceId = resolvedGameInstanceId(payload: payload, gameInstanceFilter: gameInstanceFilter) else {
                continue
            }
            if let filter = gameInstanceFilter, gameInstanceId != filter {
                continue
            }
            let key = bucketKey(gameInstanceId: gameInstanceId, regionId: regionId)

            switch event.kind {
            case .regionFound:
                let discovery = makeDiscovery(from: event, gameInstanceId: gameInstanceId, regionId: regionId)
                buckets[key, default: []].append(discovery)
            case .regionRemoved:
                if let removedId = payload[TripActivityEventPayloadKey.removedDiscoveryEventId], !removedId.isEmpty {
                    removeDiscovery(withEventId: removedId, from: &buckets)
                } else {
                    buckets.removeValue(forKey: key)
                }
            default:
                break
            }
        }

        let allDiscoveries = buckets.values.flatMap { $0 }.sorted {
            if $0.discoveredAt != $1.discoveredAt {
                return $0.discoveredAt < $1.discoveredAt
            }
            if $0.targetId != $1.targetId {
                return $0.targetId < $1.targetId
            }
            return $0.id < $1.id
        }

        let regions = aggregateFoundRegions(from: buckets)
        return (allDiscoveries, regions)
    }

    private static func bucketKey(gameInstanceId: UUID, regionId: String) -> String {
        "\(gameInstanceId.uuidString)|\(regionId)"
    }

    private static func resolvedGameInstanceId(payload: [String: String], gameInstanceFilter: UUID?) -> UUID? {
        if let s = payload[TripActivityEventPayloadKey.gameInstanceId], let u = UUID(uuidString: s) {
            return u
        }
        return gameInstanceFilter
    }

    private static func makeDiscovery(from event: TripActivityEvent, gameInstanceId: UUID, regionId: String) -> GameDiscovery {
        let payload = event.payload ?? [:]
        let participantId = payload[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
        let inputMethod = FoundRegion.InputMethod(
            rawValue: payload[TripActivityEventPayloadKey.inputMethod] ?? FoundRegion.InputMethod.list.rawValue
        ) ?? .list
        return GameDiscovery(
            id: event.id,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: regionId,
            discoveredAt: event.timestamp,
            inputMethod: inputMethod,
            location: nil
        )
    }

    private static func removeDiscovery(withEventId removedId: String, from buckets: inout [String: [GameDiscovery]]) {
        for key in Array(buckets.keys) {
            guard var list = buckets[key] else { continue }
            let countBefore = list.count
            list.removeAll { $0.id == removedId }
            guard list.count != countBefore else { continue }
            if list.isEmpty {
                buckets.removeValue(forKey: key)
            } else {
                buckets[key] = list
            }
            break
        }
    }

    private static func aggregateFoundRegions(from buckets: [String: [GameDiscovery]]) -> [FoundRegion] {
        var result: [FoundRegion] = []
        for (_, list) in buckets where !list.isEmpty {
            let sorted = list.sorted { $0.discoveredAt < $1.discoveredAt }
            guard let first = sorted.first else { continue }
            result.append(
                FoundRegion(
                    regionID: first.targetId,
                    foundAt: first.discoveredAt,
                    inputMethod: first.inputMethod,
                    foundBy: first.participantId,
                    foundAtLocation: nil
                )
            )
        }
        return result.sorted { $0.regionID < $1.regionID }
    }
}
