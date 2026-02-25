"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.writeAuditLog = writeAuditLog;
const admin = require("firebase-admin");
const db = admin.firestore();
/**
 * Write immutable audit log entry
 */
async function writeAuditLog(data) {
    const auditData = Object.assign(Object.assign({}, data), { createdAt: admin.firestore.FieldValue.serverTimestamp() });
    await db.collection("audit_logs").add(auditData);
}
//# sourceMappingURL=audit.js.map