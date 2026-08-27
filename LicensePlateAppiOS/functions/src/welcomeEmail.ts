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

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { defineSecret, defineString } from "firebase-functions/params";
import { writeAuditLog } from "./audit";
import { sendTransactionalEmail } from "./utils/email";
import {
  buildWelcomeEmailContent,
  normalizeEmail,
  profileEmailChanged,
  redactEmailAddresses,
  shouldSuppressWelcomeEmailForChild,
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

    // COPPA FR-35(c): child accounts receive no welcome email at all — no claim doc,
    // no provider call, no audit row.
    const userSnap = await db.collection("users").doc(userId).get();
    const profile = userSnap.data() ?? {};
    if (shouldSuppressWelcomeEmailForChild(profile)) {
      console.log(`welcome email suppressed for ${userId}: child account`);
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

    const emailContent = buildWelcomeEmailContent(
      profile,
      welcomeEmailEnvLabel.value()
    );
    // COPPA FR-35(a): Cloud Logging must not receive the plaintext address.
    console.log(
      `welcome email sending for ${userId} subject="${emailContent.subject}"`
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

      // COPPA FR-35(a): audit rows outlive accounts; they never carry plaintext
      // addresses. The recipient remains recoverable to the owner via the private
      // users/{uid}/private/welcomeEmail status doc, which deletes with the account.
      await writeAuditLog({
        eventType: "welcome_email_sent",
        actorId: userId,
        subjectType: "user",
        subjectId: userId,
        metadata: {
          providerMessageId: result.providerMessageId,
        },
      });
      console.log(
        `welcome email sent for ${userId}: messageId=${result.providerMessageId ?? "none"}`
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // COPPA FR-35(a): provider errors routinely embed the recipient address — scrub
      // before this reaches Cloud Logging.
      console.error(
        `welcome email failed for ${userId}: ${redactEmailAddresses(message)}`
      );

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
          error: redactEmailAddresses(message),
        },
      });
    }
  });
