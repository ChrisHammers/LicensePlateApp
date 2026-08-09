/**
 * Sends a one-time welcome email when private contact email is first set or changes.
 * Uses Resend for both development and production.
 *
 * Important: public `users/{uid}` never stores email (privacy). Contact email is written to
 * `users/{uid}/private/contact` — that is the trigger path.
 *
 * Required Firebase secrets:
 *   firebase functions:secrets:set RESEND_API_KEY
 *   firebase functions:secrets:set WELCOME_EMAIL_FROM
 *
 * Optional subject label (non-secret project param via dotenv):
 *   functions/.env.<projectId>  →  WELCOME_EMAIL_ENV_LABEL=DEV
 *   Leave unset/empty for production (no subject prefix).
 *   Example: .env.roadtrip-royale-dev-d2652
 *
 * WELCOME_EMAIL_FROM example:
 *   RoadTrip Royale <support@roadtriproyale.com>
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { defineSecret, defineString } from "firebase-functions/params";
import { writeAuditLog } from "./audit";
import { sendTransactionalEmail } from "./utils/email";
import {
  buildWelcomeEmailContent,
  normalizeEmail,
  profileEmailChanged,
} from "./welcomeEmailCore";

const db = admin.firestore();
const resendApiKey = defineSecret("RESEND_API_KEY");
const welcomeEmailFrom = defineSecret("WELCOME_EMAIL_FROM");
const welcomeEmailEnvLabel = defineString("WELCOME_EMAIL_ENV_LABEL", {
  default: "",
});

const WELCOME_EMAIL_DOC_ID = "welcomeEmail";

export const onUserProfileSendWelcomeEmail = functions
  .runWith({
    secrets: [resendApiKey, welcomeEmailFrom],
  })
  .firestore.document("users/{userId}/private/contact")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      console.log(`welcome email skipped for ${userId}: private contact deleted`);
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    if (!profileEmailChanged(before, after)) {
      console.log(`welcome email skipped for ${userId}: contact email unchanged`);
      return;
    }

    const contactEmail = normalizeEmail(after.email);
    if (!contactEmail) {
      console.log(`welcome email skipped for ${userId}: contact has no email`);
      return;
    }

    const fromAddress = welcomeEmailFrom.value().trim();
    const apiKey = resendApiKey.value().trim();
    if (!fromAddress || !apiKey) {
      console.error(
        `welcome email skipped for ${userId}: missing RESEND_API_KEY or WELCOME_EMAIL_FROM`
      );
      return;
    }

    let authUser: admin.auth.UserRecord;
    try {
      authUser = await admin.auth().getUser(userId);
    } catch (error) {
      console.error(`welcome email skipped for ${userId}: auth lookup failed`, error);
      return;
    }

    const authEmail = normalizeEmail(authUser.email);
    // Prefer Auth email when present; fall back to private contact email.
    const recipient = authEmail ?? contactEmail;

    const welcomeRef = db
      .collection("users")
      .doc(userId)
      .collection("private")
      .doc(WELCOME_EMAIL_DOC_ID);

    const claimed = await db.runTransaction(async (tx) => {
      const existing = await tx.get(welcomeRef);
      if (existing.exists && existing.data()?.sentAt) {
        return false;
      }

      tx.set(
        welcomeRef,
        {
          status: "pending",
          toEmail: recipient,
          fromEmail: fromAddress,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return true;
    });

    if (!claimed) {
      console.log(`welcome email skipped for ${userId}: already sent`);
      return;
    }

    const userSnap = await db.collection("users").doc(userId).get();
    const profile = userSnap.data() ?? {};
    const emailContent = buildWelcomeEmailContent(
      profile,
      welcomeEmailEnvLabel.value()
    );
    console.log(
      `welcome email sending for ${userId} to ${recipient} from ${fromAddress} subject="${emailContent.subject}"`
    );

    try {
      const result = await sendTransactionalEmail({
        apiKey,
        from: fromAddress,
        to: recipient,
        subject: emailContent.subject,
        html: emailContent.html,
        text: emailContent.text,
      });

      await welcomeRef.set(
        {
          status: "sent",
          toEmail: recipient,
          fromEmail: fromAddress,
          provider: "resend",
          providerMessageId: result.providerMessageId,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastError: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );

      await writeAuditLog({
        eventType: "welcome_email_sent",
        actorId: userId,
        subjectType: "user",
        subjectId: userId,
        metadata: {
          toEmail: recipient,
          fromEmail: fromAddress,
          providerMessageId: result.providerMessageId,
          contactEmail,
        },
      });
      console.log(
        `welcome email sent for ${userId}: messageId=${result.providerMessageId ?? "none"}`
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`welcome email failed for ${userId}:`, error);

      await welcomeRef.set(
        {
          status: "failed",
          toEmail: recipient,
          fromEmail: fromAddress,
          lastError: message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      await writeAuditLog({
        eventType: "welcome_email_failed",
        actorId: userId,
        subjectType: "user",
        subjectId: userId,
        metadata: {
          toEmail: recipient,
          fromEmail: fromAddress,
          error: message,
        },
      });
    }
  });
