/**
 * Sends a one-time welcome email when a user profile gains an email address.
 * Uses your existing mailbox via SMTP (no Resend or other paid sender required).
 *
 * Required Firebase secrets:
 *   firebase functions:secrets:set SMTP_HOST
 *   firebase functions:secrets:set SMTP_USER
 *   firebase functions:secrets:set SMTP_PASS
 *   firebase functions:secrets:set WELCOME_EMAIL_FROM
 *
 * WELCOME_EMAIL_FROM controls the visible From header, e.g.:
 *   RoadTrip Royale <welcome@yourdomain.com>
 *
 * Optional params (defaults shown):
 *   firebase functions:params:set SMTP_PORT 587
 *   firebase functions:params:set SMTP_SECURE false
 *
 * Common SMTP hosts:
 *   Google Workspace / Gmail: smtp.gmail.com (use an App Password for SMTP_PASS)
 *   Microsoft 365 / Outlook:  smtp.office365.com
 *   Zoho Mail:                smtp.zoho.com
 *   cPanel / hosting mail:    mail.yourdomain.com
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

const smtpHost = defineSecret("SMTP_HOST");
const smtpUser = defineSecret("SMTP_USER");
const smtpPass = defineSecret("SMTP_PASS");
const welcomeEmailFrom = defineSecret("WELCOME_EMAIL_FROM");
const smtpPort = defineString("SMTP_PORT", { default: "587" });
const smtpSecure = defineString("SMTP_SECURE", { default: "false" });

const WELCOME_EMAIL_DOC_ID = "welcomeEmail";

function parseSmtpPort(value: string): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 587;
}

export const onUserProfileSendWelcomeEmail = functions
  .runWith({
    secrets: [smtpHost, smtpUser, smtpPass, welcomeEmailFrom],
  })
  .firestore.document("users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      return;
    }

    const before = change.before.exists ? change.before.data() : null;
    if (!profileEmailChanged(before, after)) {
      return;
    }

    const fromAddress = welcomeEmailFrom.value().trim();
    const host = smtpHost.value().trim();
    const user = smtpUser.value().trim();
    const pass = smtpPass.value().trim();
    if (!fromAddress || !host || !user || !pass) {
      console.error(
        `welcome email skipped for ${userId}: missing SMTP or WELCOME_EMAIL_FROM config`
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
    if (!authEmail) {
      return;
    }

    const profileEmail = normalizeEmail(after.email);
    if (!profileEmail) {
      return;
    }

    const recipient = authEmail;
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
      return;
    }

    const emailContent = buildWelcomeEmailContent(after);
    const secure = smtpSecure.value().trim().toLowerCase() === "true";

    try {
      const result = await sendTransactionalEmail({
        smtp: {
          host,
          port: parseSmtpPort(smtpPort.value()),
          secure,
          user,
          pass,
        },
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
          provider: "smtp",
          providerMessageId: result.providerMessageId,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
          profileEmail,
        },
      });
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
