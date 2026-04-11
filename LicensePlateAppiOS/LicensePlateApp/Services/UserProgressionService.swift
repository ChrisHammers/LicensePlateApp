//
//  UserProgressionService.swift
//  LicensePlateApp
//
//  Step 16 — Observes `UserProgressionRepository` and emits typed analytics on meaningful transitions.
//

import Combine
import Foundation

@MainActor
final class UserProgressionService: ObservableObject {

    static let shared = UserProgressionService()

    private let repository: UserProgressionRepository
    private var cancellables = Set<AnyCancellable>()
    private var previousSnapshot: UserProgressionSnapshot?

    init(repository: UserProgressionRepository = .shared) {
        self.repository = repository
        repository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.handleSnapshot(snap)
            }
            .store(in: &cancellables)
    }

    /// Clears transition state (e.g. sign-out).
    func resetForSignOut() {
        previousSnapshot = nil
    }

    private func handleSnapshot(_ snapshot: UserProgressionSnapshot?) {
        guard let snapshot else {
            previousSnapshot = nil
            return
        }

        let old = previousSnapshot
        previousSnapshot = snapshot

        if old == nil {
            for key in UserProgressionMilestoneDetector.milestoneKeys(previous: nil, next: snapshot) {
                if key == "ever_competitive_first_place" {
                    AnalyticsService.shared.log(.progressionMilestoneEverCompetitiveFirstPlace)
                }
            }
            AnalyticsService.shared.log(
                .progressionSnapshotApplied(
                    totalXp: snapshot.totalXp,
                    acceptedRegionFindCount: snapshot.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: snapshot.competitiveFirstPlaceFinishes
                )
            )
            return
        }

        for key in UserProgressionMilestoneDetector.milestoneKeys(previous: old, next: snapshot) {
            if key == "ever_competitive_first_place" {
                AnalyticsService.shared.log(.progressionMilestoneEverCompetitiveFirstPlace)
            }
        }

        let dxp = UserProgressionMilestoneDetector.totalXpDelta(previous: old, next: snapshot)
        if dxp > 0 {
            AnalyticsService.shared.log(.progressionXpAwarded(delta: dxp, reason: "server_increment"))
        }

        if snapshot != old {
            AnalyticsService.shared.log(
                .progressionSnapshotApplied(
                    totalXp: snapshot.totalXp,
                    acceptedRegionFindCount: snapshot.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: snapshot.competitiveFirstPlaceFinishes
                )
            )
        }
    }
}
