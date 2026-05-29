//
//  UserProgressionService.swift
//  LicensePlateApp
//
//  Step 16 — Firestore `user_progression` listener + typed analytics.
//  Step 16 addendum — Merges server totals with local pending (offline) from `TripActivityEvent` replay parity.
//

import Combine
import Foundation

@MainActor
final class UserProgressionService: ObservableObject, ProgressionLocalAppendObserving {

    static let shared = UserProgressionService()

    private let repository: UserProgressionRepository
    private let eventRepository: TripActivityEventRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var previousEffectiveTotals: UserProgressionEffectiveTotals?
    private var refreshWorkItem: DispatchWorkItem?

    @Published private(set) var effectiveTotals: UserProgressionEffectiveTotals?

    init(
        repository: UserProgressionRepository = .shared,
        eventRepository: TripActivityEventRepositoryProtocol = TripActivityEventRepository.shared
    ) {
        self.repository = repository
        self.eventRepository = eventRepository
        repository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleRefreshPending()
            }
            .store(in: &cancellables)
    }

    /// Clears transition state (e.g. sign-out).
    func resetForSignOut() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        previousEffectiveTotals = nil
        effectiveTotals = nil
    }

    /// After a superseded or removed local event; recomputes pending so phantom XP clears.
    func handleLocalEventRemoved(id: String) {
        _ = id
        scheduleRefreshPending()
    }

    private func scheduleRefreshPending() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.recomputeEffective()
            }
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func recomputeEffective() {
        guard let uid = repository.currentObservedUserId, !uid.isEmpty else {
            effectiveTotals = nil
            return
        }

        let server = repository.snapshot ?? UserProgressionSnapshot.empty
        let applied = server.appliedProgressionEventIds

        let sessionIds: Set<UUID>
        do {
            sessionIds = try eventRepository.sessionIdsRelevantToProgression(forUserId: uid)
        } catch {
            sessionIds = []
        }

        var sessionPayloads: [(sortedEvents: [TripActivityEvent], rosterUserIds: [String], gamesById: [UUID: ProgressionGameSnapshot])] = []
        for sid in sessionIds {
            guard let trip = try? TripSessionRepository.shared.session(byId: sid) else { continue }
            let roster = trip.participants.filter { $0.leftAt == nil }.map(\.userId)
            guard roster.contains(uid) else { continue }
            guard let evs = try? eventRepository.events(sessionId: sid, limit: nil) else { continue }
            guard let games = try? GameInstanceRepository.shared.fetchByTripSession(sessionId: sid) else { continue }
            let gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.progressionGameSnapshot) })
            sessionPayloads.append((sortedEvents: evs, rosterUserIds: roster, gamesById: gamesById))
        }

        let pending = ProgressionLocalEngine.pendingDeltaAcrossSessions(
            sessions: sessionPayloads,
            subjectUserId: uid,
            serverAppliedEventIds: applied
        )
        let effective = UserProgressionEffectiveTotals.combined(server: server, pending: pending)

        let old = previousEffectiveTotals
        previousEffectiveTotals = effective
        effectiveTotals = effective

        if old == nil {
            for key in UserProgressionMilestoneDetector.milestoneKeysEffective(previous: nil, next: effective) {
                if key == "ever_competitive_first_place" {
                    AnalyticsService.shared.log(.progressionMilestoneEverCompetitiveFirstPlace)
                }
            }
            AnalyticsService.shared.log(
                .progressionSnapshotApplied(
                    totalXp: effective.totalXp,
                    acceptedRegionFindCount: effective.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: effective.competitiveFirstPlaceFinishes
                )
            )
            return
        }

        for key in UserProgressionMilestoneDetector.milestoneKeysEffective(previous: old, next: effective) {
            if key == "ever_competitive_first_place" {
                AnalyticsService.shared.log(.progressionMilestoneEverCompetitiveFirstPlace)
            }
        }

        let dxp = UserProgressionMilestoneDetector.totalXpDeltaEffective(previous: old, next: effective)
        if dxp > 0 {
            AnalyticsService.shared.log(.progressionXpAwarded(delta: dxp, reason: "effective_increment"))
        }

        if effective != old {
            AnalyticsService.shared.log(
                .progressionSnapshotApplied(
                    totalXp: effective.totalXp,
                    acceptedRegionFindCount: effective.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: effective.competitiveFirstPlaceFinishes
                )
            )
        }
    }

    func progressionDidCommitLocalActivityEvent(_ event: TripActivityEvent) {
        _ = event
        scheduleRefreshPending()
    }
}
