//
//  XpToastDiagnostics.swift
//  LicensePlateApp
//
//  TEMPORARY — §3.1.1 item 12 (2026-09-16). Standalone so the repository layer
//  (XpGrantRemoteRepository) depends on a diagnostics utility, not on the toast service's file, and
//  so removal after the owner's device pass is one file delete plus the call sites.
//

import Foundation
import os

// MARK: - Temporary diagnostics (§3.1.1 item 12, XP toast replaying lifetime history)

/// DEBUG-only trace of the XP toast's remote half: grants listener bind → snapshot (cache vs
/// server) → ledger baseline → remote absorb/seal → burst. `[XpToast]` in the Xcode console;
/// `subsystem com.HammersTech.LicensePlateApp / category XpToast` in Console.app so a device that
/// is NOT attached to Xcode can still be read. Remove once item 12 is owner-passed.
///
/// The `remote.seal` line carries a counterfactual: the toast the owner WOULD have seen had the
/// pre-item-12 baseline sealed before this snapshot (certain on a reinstall / new uid, where no
/// cached event exists; a race the old code usually won on a warm-cache relaunch). It is computed
/// with the PRE-item-12 eligibility rule (amount > 0, not base discovery, not return streak — i.e.
/// the legacy migration seal still counted, falling through to the catch-all "other" group). So on
/// an account carrying that seal the bracket reads one group line with an all-time-sized number,
/// which is exactly the reported artefact, printed at the moment it is being suppressed.
enum XpToastDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.HammersTech.LicensePlateApp", category: "XpToast")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        print("[XpToast] \(text)")
        #endif
    }

    static func shortUid(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return String(value.prefix(6))
    }

    static func sealLine(
        generation: Int,
        userId: String?,
        absorbed: Int,
        grants: [UserXpGrant],
        catalog: ProgressionCatalog,
        msSinceConfigure: Int
    ) -> String {
        var eligible = 0
        var eligibleXp = 0
        var groupIds = Set<String>()
        for grant in grants {
            guard grant.amount > 0 else { continue }
            guard grant.reason != UserXpGrantReason.regionFoundBaseDiscovery.rawValue else { continue }
            guard grant.reason != UserXpGrantReason.returnStreakDaily.rawValue else { continue }
            eligible += 1
            eligibleXp += grant.amount
            if let event = XpGainToastSourceMapper.ingestEvent(from: grant, catalog: catalog) {
                groupIds.insert(event.groupId)
            } else {
                // Suppressed by item 12 now (the migration seal); pre-fix it fell through to "other".
                groupIds.insert("other")
            }
        }
        return "remote.seal gen=\(generation) uid=\(shortUid(userId)) absorbed=\(absorbed)"
            + " eligible=\(eligible) eligibleXp=\(eligibleXp) msSinceConfigure=\(msSinceConfigure)"
            + " [PRE-FIX exposure: \(eligibleXp) XP across \(groupIds.count) group line(s) would have toasted had the baseline sealed before this snapshot]"
    }

    static func logNewRemoteGrants(
        generation: Int,
        grants: [UserXpGrant],
        newEvents: [XpGainToastIngestEvent]
    ) {
        #if DEBUG
        let newGrantIds = Set(
            newEvents.compactMap { $0.sourceId.hasPrefix("grant|") ? String($0.sourceId.dropFirst(6)) : nil }
        )
        guard !newGrantIds.isEmpty else { return }
        let fresh = grants.filter { newGrantIds.contains($0.grantId) }
        for grant in fresh.prefix(20) {
            // Grant ids embed the full uid; log a tail, like `shortUid` logs a head.
            log("remote.new gen=\(generation) idTail=\(grant.grantId.suffix(10)) reason=\(grant.reason) amount=\(grant.amount)")
        }
        if fresh.count > 20 {
            log("remote.new (+\(fresh.count - 20) more)")
        }
        #endif
    }
}
