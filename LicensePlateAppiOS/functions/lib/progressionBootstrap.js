"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ensureUserProgressionDocument = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const audit_1 = require("./audit");
const clientMetadata_1 = require("./clientMetadata");
const progressionBootstrapCore_1 = require("./progressionBootstrapCore");
const db = admin.firestore();
exports.ensureUserProgressionDocument = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = context.auth.uid;
    const clientMetadata = (0, clientMetadata_1.normalizeClientMetadata)(data === null || data === void 0 ? void 0 : data.clientMetadata);
    const ref = db.collection("user_progression").doc(userId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const defaults = (0, progressionBootstrapCore_1.buildProgressionBootstrapDefaults)(snap.data());
        tx.set(ref, Object.assign(Object.assign({}, defaults), { lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp() }), { merge: true });
    });
    await (0, audit_1.writeAuditLog)({
        eventType: "user_progression_bootstrapped",
        actorId: userId,
        subjectType: "user",
        subjectId: userId,
        clientMetadata,
    });
    return { ok: true };
});
//# sourceMappingURL=progressionBootstrap.js.map