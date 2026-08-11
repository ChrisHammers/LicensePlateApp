export interface UserProfileSnapshot {
  email?: unknown;
  firstName?: unknown;
  userName?: unknown;
}

export interface WelcomeEmailContent {
  subject: string;
  html: string;
  text: string;
  greetingName: string;
}

const APP_NAME = "RoadTrip Royale";

export function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim().toLowerCase();
  if (!trimmed || !trimmed.includes("@")) {
    return null;
  }
  return trimmed;
}

export function profileEmailChanged(
  before: UserProfileSnapshot | null | undefined,
  after: UserProfileSnapshot
): boolean {
  const nextEmail = normalizeEmail(after.email);
  if (!nextEmail) {
    return false;
  }
  const previousEmail = normalizeEmail(before?.email);
  return previousEmail !== nextEmail;
}

/**
 * COPPA FR-35(c): no welcome email is ever sent to a child account. The check reads the
 * authoritative `users/{uid}.isChildAccount` flag; missing flag ⇒ adult ⇒ send.
 */
export function shouldSuppressWelcomeEmailForChild(
  profile: Record<string, unknown> | undefined | null
): boolean {
  return profile?.isChildAccount === true;
}

const EMAIL_ADDRESS_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;

/**
 * COPPA FR-35(a): audit metadata and Cloud Logging sinks must never carry a plaintext
 * email address. Provider error messages routinely embed the recipient, so anything
 * derived from a send failure is scrubbed through this before it is logged or persisted.
 */
export function redactEmailAddresses(text: string): string {
  return text.replace(EMAIL_ADDRESS_PATTERN, "[redacted-email]");
}

/**
 * Prefixes the subject with `[LABEL]` when `envLabel` is non-empty after trim.
 * Empty / whitespace-only labels leave the subject unchanged.
 */
export function applyWelcomeEmailSubjectLabel(
  subject: string,
  envLabel?: string | null
): string {
  const label = typeof envLabel === "string" ? envLabel.trim() : "";
  if (!label) {
    return subject;
  }
  return `[${label}] ${subject}`;
}

export function buildWelcomeEmailContent(
  profile: UserProfileSnapshot,
  envLabel?: string | null
): WelcomeEmailContent {
  const firstName =
    typeof profile.firstName === "string" ? profile.firstName.trim() : "";
  const userName =
    typeof profile.userName === "string" ? profile.userName.trim() : "";
  const greetingName = firstName || userName || "there";

  const subject = applyWelcomeEmailSubjectLabel(
    `Welcome to ${APP_NAME}!`,
    envLabel
  );
  const text = [
    `Hi ${greetingName},`,
    "",
    `Welcome to ${APP_NAME}! Your account is ready.`,
    "",
    "Start a trip, invite friends or family, and see how many license plates you can spot along the way.",
    "",
    "Open the app to create your first trip and hit the road.",
    "",
    `— The ${APP_NAME} team`,
  ].join("\n");

  const html = `<!DOCTYPE html>
<html lang="en">
  <body style="margin:0;padding:0;background:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1d1d1f;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f5f7;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border-radius:16px;padding:32px 28px;">
            <tr>
              <td>
                <p style="margin:0 0 8px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#6e6e73;">Welcome</p>
                <h1 style="margin:0 0 16px;font-size:28px;line-height:1.2;">Hi ${escapeHtml(greetingName)},</h1>
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;">Welcome to <strong>${APP_NAME}</strong>. Your account is ready.</p>
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;">Start a trip, invite friends or family, and see how many license plates you can spot along the way.</p>
                <p style="margin:0 0 24px;font-size:16px;line-height:1.6;">Open the app to create your first trip and hit the road.</p>
                <p style="margin:0;font-size:14px;line-height:1.6;color:#6e6e73;">— The ${APP_NAME} team</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  return { subject, html, text, greetingName };
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
