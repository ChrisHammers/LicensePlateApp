//
//  LifetimeStatsSpec.swift
//  LicensePlateApp
//
//  Product + engineering contract for profile lifetime statistics (Master Prompt v2).
//

import Foundation

/// Namespace for documented rules only; no runtime behavior.
enum LifetimeStatsSpec {

    // MARK: - Metrics

    /// Lifetime row is a **per-user projection** over archived trip data on device:
    /// - **Completed trips**: `TripSessionState.ended` only. Cancelled trips are excluded from aggregates.
    /// - **Games played**: sum of `GameInstance` count per included trip.
    /// - **Discoveries**: sum of the subject user’s discovery count from `TripSummaryBuilder` output (roster-merged contributions).
    /// - **Weighted score**: sum of the subject user’s `ParticipantContribution.weightedScore` per included trip (parity with Travel Log / `TripSummaryBuilder` credits).
    /// - **Family-only trips**: ended trips whose **active roster** (`TripParticipant.leftAt == nil`) is non-empty and every active participant’s `userId` is in the subject’s **active family member id set** (SwiftData `FamilyMember` rows for `AppUser.activeFamilyId`). If the user has no active family, this count is always zero.
    ///
    /// **Leaver exclusion**: If the subject user’s `TripParticipant` row has `leftAt != nil`, that trip is **omitted entirely** from all lifetime aggregates (including family-only count), matching travel log / honest leave copy.

    // MARK: - Concurrency contract

    /// **Fetch (MainActor)**: Repositories load archived `TripSession`s, `GameInstance`s, activity-derived `GameDiscovery`s, and family member ids. Build **immutable `Sendable` snapshots** (`LifetimeStatsRecomputeInput`); no heavy aggregation on the main actor.
    /// **Compute (off MainActor)**: `LifetimeStatsRecomputeEngine.compute` runs in a detached task; pure CPU, uses `TripSummaryBuilder` / existing contribution paths on in-memory models reconstructed from snapshots.
    /// **Persist (MainActor)**: `UserLifetimeStatsRepository.upsert` writes `UserLifetimeStatsEntity` on the SwiftData context actor.
    /// **Single-flight**: `LifetimeStatsCoordinator` serializes overlapping refresh requests (pending coalesce) per process.
    ///
    /// **Failure**: Errors are typed, surfaced to the profile VM (`lastError`); no silent `try?` on the user-facing refresh path.

    // MARK: - Public cloud aggregate

    /// Authoritative public totals live in Firestore `public_lifetime_stats` (server-written). The app reads via
    /// `PublicLifetimeStatsRepository` and keeps a SwiftData cache; `UserLifetimeStatsEntity` remains the offline
    /// / repair projection from `LifetimeStatsRecomputeEngine`.
}
