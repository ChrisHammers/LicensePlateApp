/**
 * Scheduled retention jobs — COPPA remediation FR-49 (audit G1).
 *
 * Two daily passes, both deterministic and idempotent:
 *  - `purgeExpiredInvitesAndCodes` hard-deletes transient invite / share-code rows whose
 *    expiry passed more than the grace period ago.
 *  - `purgeExpiredAuditLogs` deletes aged `audit_logs` rows except the permanently retained
 *    consent / lifecycle event types.
 *
 * These complement, and do not replace, the every-5-minutes status-flip pass in
 * `expiration.ts`: the UI depends on seeing "expired" invites and revoked share codes, so a
 * record is flipped first and deleted only after the grace period.
 *
 * See `retentionCore.ts` for the policy constants and for why these are jobs rather than
 * Firestore native TTL policies.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  AUDIT_LOG_COLLECTION,
  AUDIT_LOG_RETENTION_MONTHS,
  EXPIRED_RECORD_DELETION_GRACE_DAYS,
  PURGEABLE_EXPIRY_COLLECTIONS,
  PurgeResult,
  auditRetentionCutoffMillis,
  expiredRecordDeletionCutoffMillis,
  isAuditRetentionExempt,
  purgeDocumentsOlderThan,
} from "./retentionCore";
import { currentRevenueCatApiKey } from "./accountDeletion";
import { reconcileConsentRecords, sweepExpiredConsentRequests } from "./consentRequests";
import {
  PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS,
  provisionalChildDeletionCutoffMillis,
  sweepExpiredProvisionalChildAccounts,
} from "./provisionalChildAccounts";

const db = admin.firestore();

// Midnight Pacific (= 3 AM Eastern) — owner-chosen fixed window, 2026-08-10.
const RETENTION_SCHEDULE = "0 0 * * *";
const RETENTION_TIME_ZONE = "America/Los_Angeles";
const RETENTION_TIMEOUT_SECONDS = 540;

/**
 * Hard-delete invites and share codes whose `expiresAt` passed more than
 * EXPIRED_RECORD_DELETION_GRACE_DAYS ago.
 */
export const purgeExpiredInvitesAndCodes = functions
  .runWith({ timeoutSeconds: RETENTION_TIMEOUT_SECONDS })
  .pubsub.schedule(RETENTION_SCHEDULE)
  .timeZone(RETENTION_TIME_ZONE)
  .onRun(async () => {
    const cutoffMillis = expiredRecordDeletionCutoffMillis(Date.now());
    const results: PurgeResult[] = [];

    for (const collection of PURGEABLE_EXPIRY_COLLECTIONS) {
      results.push(
        await purgeDocumentsOlderThan(db, {
          collection,
          timestampField: "expiresAt",
          cutoffMillis,
        })
      );
    }

    functions.logger.info("retention: purged expired invites and share codes", {
      graceDays: EXPIRED_RECORD_DELETION_GRACE_DAYS,
      cutoff: new Date(cutoffMillis).toISOString(),
      results,
    });

    return null;
  });

/**
 * COPPA FR-60(c) / FR-77 backstop: delete redemption-window child accounts that neither the
 * decline path nor the invite-expiry path got to, once they are older than
 * PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS.
 *
 * The population this catches is small by design — the inline paths handle the normal
 * outcomes — and consists mainly of the "captain never answered" case, plus anything an
 * inline failure left behind.
 *
 * It CANNOT touch a sticky post-revocation child: those accounts lost their `childDeclaredAt`
 * marker at admission and carry `wasEverInFamily: true`, and the sweep requires the marker to
 * even see a document. Their own (12-month, OD-3) retention is a separate FR-77 class.
 */
export const purgeExpiredProvisionalChildAccounts = functions
  .runWith({ timeoutSeconds: RETENTION_TIMEOUT_SECONDS })
  .pubsub.schedule(RETENTION_SCHEDULE)
  .timeZone(RETENTION_TIME_ZONE)
  .onRun(async () => {
    const cutoffMillis = provisionalChildDeletionCutoffMillis(Date.now());

    const result = await sweepExpiredProvisionalChildAccounts(db, {
      cutoffMillis,
      // Uid-only audit actor: no parent or captain authorised this, the schedule did.
      actorId: "system_retention",
      revenueCatApiKey: currentRevenueCatApiKey(),
    });

    functions.logger.info("retention: swept redemption-window child accounts", {
      windowDays: PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS,
      cutoff: new Date(cutoffMillis).toISOString(),
      result,
    });

    return null;
  });

/**
 * FR-59.1 / §312.5(c)(1): expire lapsed consent requests — "consent not obtained within a
 * reasonable time." Request → expired, join-request row retired (which lifts the FR-77
 * veto), guardian email purged, and the provisional child deleted INLINE (owner ruling
 * 2026-08-27: a refused-by-silence child's footprint does not linger). Daily rather than
 * the 5-minute pass on that pass's own rule — deletion machinery stays out of it; the
 * confirmation endpoint enforces expiry in real time regardless, so the daily lag only
 * delays cleanup, never admits on a stale link.
 */
export const expireLapsedConsentRequests = functions
  .runWith({ timeoutSeconds: RETENTION_TIMEOUT_SECONDS })
  .pubsub.schedule(RETENTION_SCHEDULE)
  .timeZone(RETENTION_TIME_ZONE)
  .onRun(async () => {
    const result = await sweepExpiredConsentRequests(db, Date.now());
    functions.logger.info("retention: expired lapsed consent requests", { result });
    return null;
  });

/**
 * §3.1.2 step 8 / FR-64 + FR-108(f)4: nightly reconcile. Re-derives FR-64's guarantee
 * from stored state — every consented child holds a sufficient consent record, every
 * confirmed email_plus grant got its plus notice. Detection only; a finding is a loud
 * error log with uid/request-id-only payload, and FR-104 owns any enforcement.
 */
export const reconcileParentalConsentRecords = functions
  .runWith({ timeoutSeconds: RETENTION_TIMEOUT_SECONDS })
  .pubsub.schedule(RETENTION_SCHEDULE)
  .timeZone(RETENTION_TIME_ZONE)
  .onRun(async () => {
    const result = await reconcileConsentRecords(db, { nowMillis: Date.now() });
    const findingCount =
      result.missingRecord.length +
      result.belowRequiredLevel.length +
      result.plusNoticeAbandoned.length +
      result.plusNoticeOverdue.length;
    if (findingCount > 0) {
      functions.logger.error(
        "FR-64 reconcile FINDINGS: consented children without sufficient consent records, or plus notices that never sent",
        { result }
      );
    } else {
      functions.logger.info("FR-64 reconcile clean", { result });
    }
    return null;
  });

/**
 * Delete `audit_logs` rows older than AUDIT_LOG_RETENTION_MONTHS, preserving the
 * consent / lifecycle event types listed in AUDIT_RETENTION_EXEMPT_EVENT_TYPES forever.
 */
export const purgeExpiredAuditLogs = functions
  .runWith({ timeoutSeconds: RETENTION_TIMEOUT_SECONDS })
  .pubsub.schedule(RETENTION_SCHEDULE)
  .timeZone(RETENTION_TIME_ZONE)
  .onRun(async () => {
    const cutoffMillis = auditRetentionCutoffMillis(Date.now());

    const result = await purgeDocumentsOlderThan(db, {
      collection: AUDIT_LOG_COLLECTION,
      timestampField: "createdAt",
      cutoffMillis,
      isExempt: (data) => isAuditRetentionExempt(data.eventType),
    });

    functions.logger.info("retention: purged aged audit logs", {
      retentionMonths: AUDIT_LOG_RETENTION_MONTHS,
      cutoff: new Date(cutoffMillis).toISOString(),
      result,
    });

    return null;
  });
