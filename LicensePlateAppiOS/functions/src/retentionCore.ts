/**
 * Retention policy core — COPPA remediation FR-49 (audit G1 / consent carve-out G-7).
 *
 * Pure policy constants plus one generic, cursor-paged purge routine. Everything here is
 * unit-testable: this module never calls `admin.firestore()` at load time. The scheduled
 * wiring lives in `retention.ts`.
 *
 * WHY SCHEDULED JOBS INSTEAD OF FIRESTORE NATIVE TTL POLICIES
 * -----------------------------------------------------------
 * Firestore supports declarative TTL, configured out-of-band with gcloud rather than in
 * this repo, e.g.:
 *
 *   gcloud firestore fields ttls update expiresAt \
 *     --collection-group=share_codes --enable-ttl
 *
 * That is cheaper than a job (no query reads, deletes are not billed as writes) and would
 * cover the transient collections. We still run jobs, for two reasons:
 *
 *  1. `audit_logs` needs a per-row carve-out. Parental-consent and account-lifecycle rows
 *     (AUDIT_RETENTION_EXEMPT_EVENT_TYPES) are durable evidence and must outlive the
 *     retention window. Native TTL is unconditional — it deletes every document whose TTL
 *     field has passed and supports no predicate — so it cannot express the exemption.
 *  2. Invites and share codes are deleted at `expiresAt + grace`, not at `expiresAt`.
 *     Native TTL fires on the field's own value, so honoring the grace period would require
 *     writing a second `deleteAfter` timestamp on every invite (a schema + write-path change
 *     across friends.ts / family.ts / tripInvites.ts / shareCodes.ts).
 *
 * Native TTL stays a valid future optimization for the transient collections: add
 * `deleteAfter = expiresAt + grace` at write time, enable a TTL policy on it, and drop the
 * invite pass from `retention.ts`. The audit pass must remain a job regardless.
 */

import * as admin from "firebase-admin";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Collection holding immutable audit rows (see `audit.ts`). */
export const AUDIT_LOG_COLLECTION = "audit_logs";

/**
 * How long a friend invite stays actionable. Replaces the previous "100 years from now"
 * sentinel, which made friend invites effectively permanent PI (FR-49b).
 */
export const FRIEND_INVITE_EXPIRY_DAYS = 30;

/**
 * Grace period between a record's `expiresAt` and its hard deletion. The status-flip pass in
 * `expiration.ts` still runs every 5 minutes so the UI keeps seeing "expired" rows; this
 * window is how long that tombstone remains visible before the row is removed for good.
 */
export const EXPIRED_RECORD_DELETION_GRACE_DAYS = 30;

/** Retention window for non-exempt `audit_logs` rows. */
export const AUDIT_LOG_RETENTION_MONTHS = 12;

/**
 * Audit event types that are PERMANENTLY retained — they are never deleted by the retention
 * job at any age.
 *
 * These rows are the durable evidence that verifiable parental consent was obtained,
 * corrected, or revoked, and that an account was deleted. Losing them would leave the app
 * unable to demonstrate COPPA compliance for a child who is still a child. Deleting a row
 * listed here is a compliance regression, not a cleanup — `retentionCore.test.ts` pins this.
 *
 * The consent event types are written by a later feature (parental consent) and do not exist
 * in the codebase yet; the list is declared here up front so the retention job is already
 * correct on the day those writers land.
 */
export const AUDIT_RETENTION_EXEMPT_EVENT_TYPES: readonly string[] = [
  "AUDIT_PARENTAL_CONSENT_GRANTED",
  "AUDIT_PARENTAL_CONSENT_CORRECTED",
  "AUDIT_PARENTAL_CONSENT_REVOKED",
  "AUDIT_CHILD_REGISTRATION_DECLARED",
  "AUDIT_ACCOUNT_DELETED",
];

/**
 * Transient collections purged on `expiresAt + grace`. Gameplay history
 * (`trip_sessions` / `activity_events`) is deliberately absent: it is retained as trip
 * history and de-identified on account deletion instead (FR-50).
 */
export const PURGEABLE_EXPIRY_COLLECTIONS: readonly string[] = [
  "invites",
  "trip_invites",
  "share_codes",
];

/** Firestore caps a write batch at 500 operations; leave headroom. */
export const RETENTION_DELETE_BATCH_SIZE = 400;

/** Upper bound on deletes per invocation so a backlog cannot blow the function timeout. */
export const RETENTION_MAX_DELETES_PER_RUN = 5000;

/**
 * Upper bound on documents *read* per invocation. Distinct from the delete bound because the
 * audit pass reads exempt rows it will not delete.
 *
 * Exempt rows sort oldest-first, so they are re-read on every run. That is fine while exempt
 * volume is small. If it ever approaches this bound the job stops making progress; the fix at
 * that point is to stamp a `retentionExempt: true` field at write time in `audit.ts` and add
 * `.where("retentionExempt", "!=", true)` here, rather than raising the bound indefinitely.
 */
export const RETENTION_MAX_SCANNED_PER_RUN = 20000;

/** True when this audit event type must survive retention cleanup forever. */
export function isAuditRetentionExempt(eventType: unknown): boolean {
  return (
    typeof eventType === "string" &&
    AUDIT_RETENTION_EXEMPT_EVENT_TYPES.includes(eventType)
  );
}

/** Absolute expiry stamped on a newly created friend invite. */
export function friendInviteExpiresAtMillis(
  nowMillis: number,
  days: number = FRIEND_INVITE_EXPIRY_DAYS
): number {
  return nowMillis + days * MS_PER_DAY;
}

/**
 * Records whose `expiresAt` is strictly before this instant are eligible for hard deletion.
 */
export function expiredRecordDeletionCutoffMillis(
  nowMillis: number,
  graceDays: number = EXPIRED_RECORD_DELETION_GRACE_DAYS
): number {
  return nowMillis - graceDays * MS_PER_DAY;
}

/**
 * Audit rows created strictly before this instant are eligible for deletion unless exempt.
 *
 * Calendar-month arithmetic in UTC, so the window is stable regardless of deploy region.
 * Day-of-month overflow (e.g. Feb 29 minus 12 months) rolls forward by a day, which is
 * immaterial for a 12-month window and keeps the function deterministic.
 */
export function auditRetentionCutoffMillis(
  nowMillis: number,
  months: number = AUDIT_LOG_RETENTION_MONTHS
): number {
  const cutoff = new Date(nowMillis);
  cutoff.setUTCMonth(cutoff.getUTCMonth() - months);
  return cutoff.getTime();
}

export interface PurgeOptions {
  /** Top-level collection to sweep. */
  collection: string;
  /** Timestamp field the cutoff is compared against. */
  timestampField: string;
  /** Documents strictly older than this are deleted (unless exempt). */
  cutoffMillis: number;
  /** Rows for which this returns true are read, counted, and left alone. */
  isExempt?: (data: admin.firestore.DocumentData) => boolean;
  batchSize?: number;
  maxDeletes?: number;
  maxScanned?: number;
}

export interface PurgeResult {
  collection: string;
  /** Documents read. */
  scanned: number;
  /** Documents deleted. */
  deleted: number;
  /** Documents read and preserved by the carve-out. */
  exempt: number;
  /** True when a per-run bound stopped the sweep early; the next run resumes the backlog. */
  truncated: boolean;
}

/**
 * Delete every document in `collection` whose `timestampField` predates the cutoff, except
 * those the caller exempts.
 *
 * Deterministic and idempotent: the sweep is ordered by the timestamp field and paged with a
 * document cursor, so a second run over an already-clean collection reads one empty page and
 * deletes nothing, and a run interrupted mid-way simply resumes from the oldest survivor.
 * Cursor paging (rather than re-querying from the start) is what keeps the audit pass
 * terminating when a whole page is exempt.
 *
 * Documents missing `timestampField` are invisible to the range filter and are never deleted.
 *
 * Queries are an inequality plus an `orderBy` on the same single field, which Firestore serves
 * from the automatic single-field index — no composite index is required for this sweep.
 */
export async function purgeDocumentsOlderThan(
  db: admin.firestore.Firestore,
  options: PurgeOptions
): Promise<PurgeResult> {
  const batchSize = options.batchSize ?? RETENTION_DELETE_BATCH_SIZE;
  const maxDeletes = options.maxDeletes ?? RETENTION_MAX_DELETES_PER_RUN;
  const maxScanned = options.maxScanned ?? RETENTION_MAX_SCANNED_PER_RUN;
  const cutoff = admin.firestore.Timestamp.fromMillis(options.cutoffMillis);

  let scanned = 0;
  let deleted = 0;
  let exempt = 0;
  let truncated = false;
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    if (deleted >= maxDeletes || scanned >= maxScanned) {
      truncated = true;
      break;
    }

    let query: admin.firestore.Query = db
      .collection(options.collection)
      .where(options.timestampField, "<", cutoff)
      .orderBy(options.timestampField, "asc")
      .limit(batchSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
    scanned += snapshot.size;

    const batch = db.batch();
    let pendingDeletes = 0;
    for (const doc of snapshot.docs) {
      if (options.isExempt && options.isExempt(doc.data())) {
        exempt += 1;
        continue;
      }
      batch.delete(doc.ref);
      pendingDeletes += 1;
    }

    if (pendingDeletes > 0) {
      await batch.commit();
      deleted += pendingDeletes;
    }

    if (snapshot.size < batchSize) {
      break;
    }
  }

  return { collection: options.collection, scanned, deleted, exempt, truncated };
}
