/**
 * FR-77 / NP-3 row 12 — OD-3 DECIDED 2026-08-30 (owner): 36 months.
 *
 * The trip survives; the PLACE-TRAIL ages out. A trip's names, discoveries and scores are the
 * product's purpose and are retained for as long as the account lives (that is row 12's whole
 * asymmetry with row 11). What has no continuing purpose is the coarse coordinate stamped on
 * each `region_found` — it answered "where did we spot that plate?" while the trip was alive,
 * and its value decays to nothing while its sensitivity does not. So once a trip ended longer
 * ago than the OD-3 window, this sweep strips the location keys off its events and leaves
 * everything else exactly as it was.
 *
 * In practice this is an ADULT-account job: FR-33/75/76 mean a child's events never carry
 * location at all (the client does not send it and the server strips it if they do). The job
 * is age-scoped rather than actor-scoped anyway, because a coordinate's decay does not depend
 * on who recorded it.
 *
 * THE LOAD-BEARING CONSTRAINT (FR-77, late-replay ledger)
 * ------------------------------------------------------
 * This sweep strips `LOCATION_PAYLOAD_KEYS` and NOTHING ELSE. In particular
 * `SERVER_STAMPED_PAYLOAD_KEYS` — `lateReplay` and `serverCommittedAt` — must survive
 * untouched: `lateReplay` is what freezes a competitive outcome under FR-28h/D-25 and what
 * `publicLifetimeStatsOnLateReplay` reconciles against, and `serverCommittedAt` is the
 * accept-order tie-break. An aging job that quietly dropped either would rewrite settled
 * gameplay history three years after the fact. `xpDayKey` idempotence is preserved for the
 * same reason. Pinned by test.
 *
 * WHY THE WHOLE PAYLOAD MAP IS REWRITTEN
 * -------------------------------------
 * `update({ payload })` replaces the map rather than deleting dotted subkeys, which is how
 * `accountDeletionDeidentify.ts` already strips these same keys — one mechanism, not two. The
 * rewrite is a read-modify-write, so it could in principle clobber a concurrent payload
 * write; nothing writes an existing event's payload except this sweep and the de-identify
 * pass, and the only server stamp that lands after creation (FR-28h `lateReplay`) is bounded
 * by a replay horizon measured in days against this job's three years.
 *
 * IDEMPOTENT BY CONSTRUCTION: `stripLocationPayloadKeys` returns `null` when a payload holds
 * no location key, so a second run over an already-aged trip reads its events and writes
 * nothing at all.
 */

import * as admin from "firebase-admin";
import { LOCATION_PAYLOAD_KEYS } from "./payloadKeys";

type Firestore = admin.firestore.Firestore;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * The canonical trip-end stamp on `trip_sessions/{id}`, written by
 * `publishTripSessionCanonical` (and by the deletion sweep when it ends an orphaned trip).
 * A live trip carries an explicit `null` here, which is why the per-doc guard below re-reads
 * it rather than trusting the range filter alone.
 */
export const SESSION_ENDED_AT_FIELD = "canonicalEndedAt";

/** OD-3 (owner, 2026-08-30): 36 months, implemented as days for millis math. */
export const LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT = 1095;

/**
 * Dev knob, same pattern as REVOKED_CHILD_RETENTION_DAYS: set
 * LOCATION_PAYLOAD_RETENTION_DAYS in the functions env to shrink the window for a live
 * verification (0 = every ended trip ages immediately — deliberately NOT set in the dev env
 * file; setting it is a conscious destructive-test act).
 */
export function locationPayloadRetentionDays(): number {
  // An unset/empty knob must fall to the OD-3 default — `Number("")` is 0, and a 0-day
  // default would strip every ended trip on the first nightly run. Pinned by test.
  const raw = process.env.LOCATION_PAYLOAD_RETENTION_DAYS;
  if (raw === undefined || raw.trim() === "") {
    return LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0
    ? parsed
    : LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT;
}

export function locationPayloadAgingCutoffMillis(
  nowMillis: number,
  windowDays: number = locationPayloadRetentionDays()
): number {
  return nowMillis - windowDays * MS_PER_DAY;
}

/** Upper bound on sessions REWRITTEN per invocation, so a backlog cannot blow the timeout. */
export const LOCATION_AGING_MAX_SESSIONS = 25;
/**
 * Upper bound on `trip_sessions` docs READ per invocation. Distinct from the rewrite bound
 * because this job, unlike every other retention sweep here, is NOT self-quenching: stripping
 * a trip's location keys does not move it out of the `canonicalEndedAt < cutoff` filter, so an
 * already-clean aged trip sorts oldest-first and is re-read on every subsequent run.
 *
 * That is affordable for as long as the aged population is small, and it cannot be anything
 * else before 2029 — the app is unreleased, so no trip can be 36 months old for years. If the
 * clean-session count in this job's log ever approaches this bound the job stops making
 * progress, and the fix at that point is to stamp a `locationPayloadsAgedAtMillis` marker at
 * strip time and filter the discovery query on it (a composite index), NOT to raise the bound
 * indefinitely. Same trade, and same escape hatch, as the exempt-row note on
 * RETENTION_MAX_SCANNED_PER_RUN in `retentionCore.ts`.
 */
export const LOCATION_AGING_MAX_SCANNED = 500;
export const LOCATION_AGING_PAGE_SIZE = 50;
/** Events read per inner page. Stays under Firestore's 500-op batch cap with headroom. */
export const LOCATION_AGING_EVENT_PAGE_SIZE = 400;

/**
 * Millis for a stored trip-end stamp, or `null` when the field is not one.
 *
 * Recognises a Firestore `Timestamp` (production) and a raw millis number (the FakeFirestore
 * harness's documented stand-in — it JSON-clones every value, so a `Timestamp` there comes
 * back method-less). An explicit `null`, a missing field, or anything else means "this trip
 * has not ended", and an un-ended trip is never aged.
 */
export function sessionEndedAtMillis(
  data: Record<string, unknown> | undefined | null
): number | null {
  const value = data?.[SESSION_ENDED_AT_FIELD];
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (
    value &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    const millis = (value as { toMillis: () => number }).toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

/**
 * Strip the location keys from one event payload, or return `null` when there is nothing to
 * strip. Every other key — server-stamped bookkeeping included — is copied through verbatim.
 */
export function stripLocationPayloadKeys(
  payload: unknown
): Record<string, unknown> | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }
  const source = payload as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  let stripped = false;
  for (const [key, value] of Object.entries(source)) {
    if (LOCATION_PAYLOAD_KEYS.includes(key)) {
      stripped = true;
      continue;
    }
    out[key] = value;
  }
  return stripped ? out : null;
}

export interface LocationPayloadAgingResult {
  /** `trip_sessions` docs read. */
  scannedSessions: number;
  /** Sessions that actually had at least one event rewritten. */
  agedSessions: number;
  /**
   * Aged-eligible sessions that held no location key at all — the population this job
   * re-reads on every run (see the bound note on LOCATION_AGING_MAX_SCANNED). Logged so the
   * re-read volume is visible before it ever becomes the binding constraint.
   */
  cleanSessions: number;
  /** Events whose payload lost location keys. */
  strippedEvents: number;
  skipped: {
    /** Returned by the range filter but not genuinely an ended, aged trip. */
    notAgedEndedTrip: number;
  };
  /** True when a per-run bound stopped the sweep early; the next run resumes the backlog. */
  truncated: boolean;
}

/** Rewrite one session's aged events. Returns how many were actually changed. */
async function stripLocationFromSessionEvents(
  db: Firestore,
  sessionRef: admin.firestore.DocumentReference
): Promise<number> {
  const events = sessionRef.collection("activity_events");
  let cursor: string | null = null;
  let stripped = 0;

  for (;;) {
    let query: admin.firestore.Query = events
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(LOCATION_AGING_EVENT_PAGE_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let pending = 0;
    for (const doc of snapshot.docs) {
      const payload = stripLocationPayloadKeys(doc.data()?.payload);
      if (!payload) continue;
      batch.update(doc.ref, { payload });
      pending += 1;
    }
    if (pending > 0) {
      await batch.commit();
      stripped += pending;
    }

    if (snapshot.size < LOCATION_AGING_EVENT_PAGE_SIZE) break;
    cursor = snapshot.docs[snapshot.docs.length - 1].id;
  }

  return stripped;
}

/**
 * Strip location payload keys from the `activity_events` of every trip that ended before
 * `cutoffMillis`.
 *
 * Session discovery is a single-field inequality + `orderBy` on the same field, so Firestore
 * serves it from the automatic single-field index — no composite index to deploy. Cursor-paged
 * because the sweep does not change `canonicalEndedAt`: unlike the status-flip passes, this
 * query is not self-quenching, so a cursor is what keeps it terminating.
 */
export async function ageLocationPayloadsOnEndedTrips(
  db: Firestore,
  options: {
    cutoffMillis: number;
    maxSessions?: number;
    maxScanned?: number;
    pageSize?: number;
  }
): Promise<LocationPayloadAgingResult> {
  const maxSessions = options.maxSessions ?? LOCATION_AGING_MAX_SESSIONS;
  const maxScanned = options.maxScanned ?? LOCATION_AGING_MAX_SCANNED;
  const pageSize = options.pageSize ?? LOCATION_AGING_PAGE_SIZE;
  const cutoff = admin.firestore.Timestamp.fromMillis(options.cutoffMillis);

  const result: LocationPayloadAgingResult = {
    scannedSessions: 0,
    agedSessions: 0,
    cleanSessions: 0,
    strippedEvents: 0,
    skipped: { notAgedEndedTrip: 0 },
    truncated: false,
  };
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    if (result.agedSessions >= maxSessions || result.scannedSessions >= maxScanned) {
      result.truncated = true;
      break;
    }

    let query: admin.firestore.Query = db
      .collection("trip_sessions")
      .where(SESSION_ENDED_AT_FIELD, "<", cutoff)
      .orderBy(SESSION_ENDED_AT_FIELD, "asc")
      .limit(pageSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;
    cursor = snapshot.docs[snapshot.docs.length - 1];
    result.scannedSessions += snapshot.size;

    for (const doc of snapshot.docs) {
      if (result.agedSessions >= maxSessions) {
        result.truncated = true;
        break;
      }

      // Not redundant with the query. A live trip carries an explicit `canonicalEndedAt:
      // null`, and in real Firestore null sorts BELOW every Timestamp — so a `<` filter
      // hands back trips that are still being played. Stripping a live trip's location
      // keys would break the running map view, so the guard is what actually decides.
      const endedAt = sessionEndedAtMillis(doc.data());
      if (endedAt === null || endedAt >= options.cutoffMillis) {
        result.skipped.notAgedEndedTrip += 1;
        continue;
      }

      const stripped = await stripLocationFromSessionEvents(db, doc.ref);
      if (stripped > 0) {
        result.agedSessions += 1;
        result.strippedEvents += stripped;
      } else {
        result.cleanSessions += 1;
      }
    }

    if (snapshot.size < pageSize) break;
  }

  return result;
}
