//
//  FamilyPendingRequestLifetime.swift
//  LicensePlateApp
//

import Foundation

/// How long a pending join request stays answerable, rendered for the captain.
///
/// Device pass 2026-08-17: a share code expired and its pending row simply stayed, looking
/// exactly like a live one — "expiry never clears it visually". The server fix decouples the
/// row from the code's 15-minute redemption window and gives it its own 7-day decision window
/// (`pendingJoinRequestExpiry.ts` carries the full argument). This is the captain's half of
/// that: the deadline is on screen from the start, so the row is never a mystery, and the
/// moment it passes the row goes visibly TERMINAL instead of quietly disappearing on the next
/// server sweep.
///
/// The client only ever renders this state — it never decides it. The server sweep is the
/// authority and retires the row within five minutes; until then a locally-expired row is
/// shown disabled rather than offering an Approve the server would refuse.
enum FamilyPendingRequestLifetime {
    /// MUST equal `PENDING_JOIN_REQUEST_TTL_DAYS` in `functions/src/pendingJoinRequestExpiry.ts`,
    /// which in turn equals FR-60(c)'s `PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS`. A client that
    /// disagreed would either grey out a row the server still accepts, or offer an Approve the
    /// server has already refused.
    static let days = 7

    enum Remaining: Equatable {
        /// Past the window. The row is terminal; the server retires it on its next sweep.
        case expired
        /// Less than 24 hours left.
        case lastDay
        /// Whole days remaining, always >= 1.
        case days(Int)
    }

    static func deadline(createdAt: Date) -> Date {
        createdAt.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60)
    }

    static func remaining(createdAt: Date, now: Date = .now) -> Remaining {
        let secondsLeft = deadline(createdAt: createdAt).timeIntervalSince(now)
        guard secondsLeft > 0 else { return .expired }
        let daysLeft = Int(secondsLeft / (24 * 60 * 60))
        return daysLeft < 1 ? .lastDay : .days(daysLeft)
    }

    static func isExpired(createdAt: Date, now: Date = .now) -> Bool {
        remaining(createdAt: createdAt, now: now) == .expired
    }

    /// Short status line for the approval row. Separate keys rather than a plural rule: the
    /// day-count form is only ever reached with `count >= 1`, and "today"/"expired" are
    /// different sentences, not different plurals.
    static func localizedLabel(createdAt: Date, now: Date = .now) -> String {
        switch remaining(createdAt: createdAt, now: now) {
        case .expired:
            return "family.pending.expired".localized
        case .lastDay:
            return "family.pending.expires_today".localized
        case .days(let count):
            return count == 1
                ? "family.pending.expires_tomorrow".localized
                : "family.pending.expires_in_days".localized(count)
        }
    }
}
