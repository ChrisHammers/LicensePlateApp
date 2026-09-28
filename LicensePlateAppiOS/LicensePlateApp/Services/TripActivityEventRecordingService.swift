//
//  TripActivityEventRecordingService.swift
//  LicensePlateApp
//
//  Step 07 — Single path: durably append activity event, then ensure sync queue row (idempotent per event id).
//

import Foundation

@MainActor
protocol TripActivityEventRecordingProtocol: AnyObject {
    func recordForSync(_ event: TripActivityEvent) throws
}

@MainActor
final class TripActivityEventRecordingService: TripActivityEventRecordingProtocol {

    static let shared = TripActivityEventRecordingService(
        tripActivityEventRepository: TripActivityEventRepository.shared,
        syncCoordinator: SyncCoordinator.shared
    )

    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let syncCoordinator: SyncCoordinatorProtocol
    private weak var progressionAppendObserver: ProgressionLocalAppendObserving?

    init(
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        syncCoordinator: SyncCoordinatorProtocol
    ) {
        self.tripActivityEventRepository = tripActivityEventRepository
        self.syncCoordinator = syncCoordinator
    }

    func setProgressionAppendObserver(_ observer: ProgressionLocalAppendObserving?) {
        progressionAppendObserver = observer
    }

    func recordForSync(_ event: TripActivityEvent) throws {
        let didInsert = try tripActivityEventRepository.appendIfAbsent(event)
        try syncCoordinator.ensureGameplayEventEnqueued(sessionId: event.sessionId, eventId: event.id)
        GameplaySyncDiagnostics.log(
            "enqueue ev=\(GameplaySyncDiagnostics.short(event.id)) kind=\(event.kind.rawValue) "
            + "sid=\(GameplaySyncDiagnostics.short(event.sessionId)) inserted=\(didInsert ? 1 : 0)"
        )
        syncCoordinator.scheduleDebouncedGameplaySyncFlushIfOnline()
        if didInsert {
            progressionAppendObserver?.progressionDidCommitLocalActivityEvent(event)
        }
    }
}
