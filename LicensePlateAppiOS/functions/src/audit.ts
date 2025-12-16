import * as admin from "firebase-admin";

const db = admin.firestore();

export interface AuditLogData {
  eventType: string;
  actorId: string;
  subjectType: "user" | "family" | "invite" | "friendship";
  subjectId: string;
  metadata?: Record<string, any>;
  ipHash?: string;
  deviceIdHash?: string;
}

/**
 * Write immutable audit log entry
 */
export async function writeAuditLog(data: AuditLogData): Promise<void> {
  const auditData = {
    ...data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection("audit_logs").add(auditData);
}

