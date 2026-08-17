//
//  FamilyRosterPublishPolicy.swift
//  LicensePlateApp
//

import Foundation

/// Whether a RE-READ of the local roster may replace the one already on screen.
///
/// Device pass 2026-08-17 (captain regression). Every family surface derives "am I a
/// captain?" from one thing — is MY row in `members`? — so an empty `members` is not a
/// neutral state, it is an authorization answer. `FamilyDashboardViewModel.canManageFamily`
/// and `FamilySettingsViewModel.isCaptainOrCreator` both return false the instant the roster
/// is blank, and every captain control disappears with them.
///
/// The refresh paths were publishing `familyRepository.getMembers(...)` UNCONDITIONALLY, and
/// that read has four ways to answer `[]` without the server ever having said so:
///
///   * `getMembers` returns `[]` when the repository has no `ModelContext` yet;
///   * it returns `[]` when the SwiftData fetch throws (`try? ... ?? []` swallows it);
///   * `pruneLocalMembers` empties the table whenever a members snapshot arrives empty —
///     including a cache-served one during a cold start;
///   * a fetch that failed leaves the store at whatever the last prune left behind.
///
/// So a transient local read decided the user was no longer a captain, and — because
/// `family` is a separate property that nothing cleared — the screen kept rendering the
/// family, the members section and the pending rows while every manage control vanished.
/// That is the exact shape the owner reported.
///
/// The dashboard's `familyRepository.$familyMembers` sink already encoded this rule inline
/// ("only assign if non-empty"); the two `refreshMemberIdentitiesIfNeeded` paths and the
/// child-projection observer did not. This is that rule, named once, so all four agree.
///
/// A roster that legitimately becomes empty is NOT this case and is not routed through here:
/// leaving, deletion, inactivation and "no active family" all clear `members` explicitly.
/// You are always a member of your own family, so a *re-read* that finds nobody is always a
/// local artifact, never news.
enum FamilyRosterPublishPolicy {

    /// - Parameters:
    ///   - refreshed: what the local store just answered.
    ///   - current: what the surface is showing now.
    /// - Returns: `true` when `refreshed` may be published.
    static func shouldPublish(refreshed: [FamilyMember], current: [FamilyMember]) -> Bool {
        !refreshed.isEmpty || current.isEmpty
    }
}
