//
//  IdentityRenderPolicy.swift
//  LicensePlateApp
//
//  v4 FR-102(d), landed at FR-100 (F-60)'s `.export` strictness only — the strictest
//  consumer arrives first. The `.inApp` lattice (subject-keyed, viewer-in-family test,
//  `callerIsConsentedChildFamilyPeerOf` reuse) is F-62's completion; nothing here may
//  fork a second implementation when it lands — F-62 extends THIS type.
//
//  FR-100(a), OD-10 (decided + refined 2026-08-15): exactly two outcomes per exported
//  participant row, decided by SUBJECT, never by viewer —
//    • server-resolved non-child ⇒ username (adults keep their names; that is the
//      point of sharing);
//    • everything else — child by ANY evidence, and unresolved/nil-held/cold-cache —
//      ⇒ the same neutral positional label ("Player 2").
//  One token for both non-name cases, deliberately: the export must not disclose
//  WHICH reason applied, since "this one is a child" is itself information about a
//  child. This is v2.1 FR-19's asymmetric trust applied to publication: only a
//  server-resolved answer earns a name; a missing, cached-only, or held signal never
//  does. A child cannot be published under any resolution failure, and an adult's
//  worst case is a neutral label on one card.
//
//  Labels are positional WITHIN one card (row order), never a pseudonym stable
//  across trips — a stable one would itself become an identifier.
//

import Foundation

/// Per-subject identity evidence at export time, assembled by
/// `ShareCardIdentityResolver` from the session-fresh sources. Value-typed so the
/// policy stays pure and the matrix stays testable.
struct ExportIdentityEvidence: Equatable, Sendable {
    /// A server-resolved `users/{uid}` read THIS SESSION answered "not a child"
    /// (absent key on an existing doc counts, per §4 semantics — an adult's doc never
    /// carries the key). Cached, ratcheted, held, or missing signals never set this.
    var serverResolvedNotChild = false
    /// Child by ANY evidence: the family `isChild` projection, a session resolution
    /// of `true`, or — for the sharer's own row — the session's own child posture.
    var anyChildEvidence = false
}

enum IdentityRenderPolicy {
    /// FR-102(d): a caller must name its strictness explicitly; adding an export
    /// surface is a visible decision, never an inherited default. `.inApp` is F-62.
    enum Strictness: Equatable, Sendable {
        case export
    }

    /// The one string both non-name outcomes share.
    static func neutralLabel(position: Int) -> String {
        "trip_summary.share.neutral_player %d".localized(position)
    }

    /// FR-100(a): resolve one exported row's display string. `position` is the
    /// 1-based row order within THIS card.
    static func exportDisplayName(
        rawDisplayName: String?,
        position: Int,
        evidence: ExportIdentityEvidence
    ) -> String {
        guard evidence.serverResolvedNotChild, !evidence.anyChildEvidence else {
            return neutralLabel(position: position)
        }
        guard let name = rawDisplayName, !name.isEmpty else {
            // A resolved adult with no hydrated name still never leaks a uid.
            return neutralLabel(position: position)
        }
        return name
    }
}

/// Assembles per-participant evidence from the live session sources and produces the
/// complete uid → exported-display-string map for one card. Every ranked participant
/// gets an entry, so the card never needs a fallback that could echo a raw uid
/// (the pre-FR-100 card fell back to the participantId itself — deleted).
@MainActor
enum ShareCardIdentityResolver {
    static func exportDisplayNames(
        summary: TripSummary,
        currentUserId: String?,
        hydratedDisplayNames: [String: String],
        userRepository: UserRepository = .shared,
        familyRepository: FamilyRepository = .shared,
        // Resolved in the body, not as a default argument — the coordinator is
        // main-actor isolated and default arguments evaluate nonisolated (the same
        // hazard EffectiveSettingsResolver documents for `.live`).
        currentSessionChildRestricted: Bool? = nil
    ) -> [String: String] {
        let sessionChildRestricted = currentSessionChildRestricted
            ?? ChildSessionPostureCoordinator.shared.isLocationRestrictedForCurrentFlow
        var tokens: [String: String] = [:]
        for (index, row) in summary.rankedParticipants.enumerated() {
            let uid = row.contribution.participantId
            let resolution = userRepository.isChildAccount(for: uid)
            let familyFlagged = familyRepository.childMemberFlags.values
                .contains { $0[uid] == true }
            let ownChildPosture = uid == currentUserId && sessionChildRestricted
            let evidence = ExportIdentityEvidence(
                serverResolvedNotChild: resolution == false,
                anyChildEvidence: resolution == true || familyFlagged || ownChildPosture
            )
            tokens[uid] = IdentityRenderPolicy.exportDisplayName(
                rawDisplayName: hydratedDisplayNames[uid],
                position: index + 1,
                evidence: evidence
            )
        }
        return tokens
    }
}
