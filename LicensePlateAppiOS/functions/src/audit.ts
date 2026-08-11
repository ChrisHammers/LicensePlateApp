import * as admin from "firebase-admin";
import type { ClientMetadata } from "./clientMetadata";

export interface AuditLogData {
  eventType: string;
  actorId: string;
  subjectType: "user" | "family" | "invite" | "friendship" | "trip_session";
  subjectId: string;
  metadata?: Record<string, any>;
  clientMetadata?: ClientMetadata | null;
  ipHash?: string;
  deviceIdHash?: string;
}

/**
 * Write immutable audit log entry
 *
 * Rows are retained for AUDIT_LOG_RETENTION_MONTHS and then deleted by the daily job in
 * `retention.ts`, EXCEPT the consent / lifecycle event types listed in
 * AUDIT_RETENTION_EXEMPT_EVENT_TYPES (`retentionCore.ts`), which are kept forever as
 * parental-consent evidence. Add any new durable-evidence event type to that list.
 */
export async function writeAuditLog(data: AuditLogData): Promise<void> {
  await writeAuditLogTo(admin.firestore(), data);
}

/**
 * Same as `writeAuditLog`, but against an explicit Firestore handle so callers that are
 * unit-tested with `testSupport/fakeFirestore.ts` (child-consent lifecycle, account deletion)
 * can write audit rows without touching the real Admin SDK.
 */
export async function writeAuditLogTo(
  db: admin.firestore.Firestore,
  data: AuditLogData
): Promise<void> {
  const auditData: Record<string, unknown> = {
    eventType: data.eventType,
    actorId: data.actorId,
    subjectType: data.subjectType,
    subjectId: data.subjectId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (data.metadata && Object.keys(data.metadata).length > 0) {
    auditData.metadata = data.metadata;
  }
  if (data.clientMetadata) {
    auditData.clientMetadata = data.clientMetadata;
  }
  if (data.ipHash) {
    auditData.ipHash = data.ipHash;
  }
  if (data.deviceIdHash) {
    auditData.deviceIdHash = data.deviceIdHash;
  }

  await db.collection("audit_logs").add(auditData);
}

