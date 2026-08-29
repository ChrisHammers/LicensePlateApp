/**
 * FR-59/FR-59.1 email_plus — pure logic for the consent-request lifecycle, and
 * FR-59.2/FR-108's assurance levels (§3.1.2 steps 1–5).
 *
 * Everything here is deterministic and Firestore-free so the vitest suites can pin the
 * whole decision surface. The dangerous parts live here on purpose:
 *
 *  - THE NONCE IS THE ENTIRE AUTH for the confirmation endpoint. It is minted with
 *    `crypto.randomBytes` (128 bits), travels only inside the emailed link, and is stored
 *    HASHED (sha256) — a Firestore read (rules deny clients, but defense in depth) or a
 *    backup never yields a usable link. Comparison is `timingSafeEqual` over digests.
 *
 *  - THE ROW STATUS IS DISPLAY, NEVER AUTHORITY. `firestore.rules` lets a captain's
 *    client write `status` strings onto pending rows (`hasOnly(["status","resolvedAt"])`),
 *    so admission authority lives in the server-only `consent_requests` document alone.
 *    The confirmation transaction re-validates everything from that document.
 *
 * §312.5(c)(1): the guardian's email in the request document is the parent's online
 * contact information collected for the purpose of obtaining consent — permitted
 * pre-consent. It lives ONLY in the server-only request doc (never audit metadata; the
 * `assertUidOnly` interlock would throw) and is purged with the request lifecycle.
 */

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

// ---------------------------------------------------------------------------
// FR-59.2 / FR-108 — consent assurance levels
// ---------------------------------------------------------------------------

/**
 * The level lattice, pinned as a closed map (v4 FR-108(a); Swift mirror rides the
 * client wave — parity test joins it there). Levels are DATA at MVP: zero user-facing
 * copy. Level 0 is the absence of a sufficient record (FR-60 local-only posture), so it
 * never appears on a record.
 */
export const CONSENT_ASSURANCE_LEVELS = {
  email_plus: 1,
  card_transaction: 2,
  id_verification: 2,
} as const;

export type ConsentMethod = keyof typeof CONSENT_ASSURANCE_LEVELS;

/**
 * Server-owned required level (FR-108(b)). MVP default: 1 for every scope, per the
 * owner's 2026-08-27 ruling (email_plus at Level 1). Raising it later flows through
 * FR-104's re-affirmation pipeline — see FR-108(c); this constant is the compile-time
 * floor, and the runtime knob rides the FR-104 wave.
 */
export const REQUIRED_CONSENT_LEVEL = 1;

export const ConsentAssurancePolicy = {
  level(method: ConsentMethod): number {
    return CONSENT_ASSURANCE_LEVELS[method];
  },
  /** A record below the required level is STALE, not revoked (FR-108(b)). */
  isRecordSufficient(recordLevel: unknown, required: number = REQUIRED_CONSENT_LEVEL): boolean {
    return typeof recordLevel === "number" && recordLevel >= required;
  },
};

// ---------------------------------------------------------------------------
// Consent-request lifecycle
// ---------------------------------------------------------------------------

export const CONSENT_REQUESTS_COLLECTION = "consent_requests";

/**
 * 72 hours. Long enough for a guardian who approves on the road and reads email at
 * night; short enough that "consent not obtained within a reasonable time" (§312.5(c)(1)
 * deletion condition) has a concrete clock. Owner-tunable default (OD-4/OD-5 family);
 * the FR-77 7-day backstop sits behind it regardless.
 */
export const CONSENT_REQUEST_TTL_MS = 72 * 60 * 60 * 1000;

/** Endpoint brute-force bound — attempts are counted on the request document itself. */
export const CONSENT_CONFIRM_MAX_ATTEMPTS = 20;

export const CONSENT_REQUEST_STATUS = {
  pending: "pending",
  confirmed: "confirmed",
  expired: "expired",
  superseded: "superseded",
} as const;

/**
 * Owner ruling 2026-08-28: mid-membership child flagging (`setFamilyMemberChildStatus`)
 * routes through the SAME email_plus machinery instead of granting inline. The request
 * document carries which lifecycle it belongs to:
 *  - `join_admission`: the original shape — confirmation ADMITS (membership + record).
 *  - `member_flag`: the child is ALREADY a member; protections applied at flag time;
 *    confirmation writes the consent record and clears the pending marker; expiry
 *    REMOVES the member (the account survives as a sticky restricted child).
 * Absent field reads as `join_admission` (every pre-existing request).
 */
export const CONSENT_REQUEST_KIND = {
  joinAdmission: "join_admission",
  memberFlag: "member_flag",
} as const;

export type ConsentRequestKind =
  (typeof CONSENT_REQUEST_KIND)[keyof typeof CONSENT_REQUEST_KIND];

export function consentRequestKind(value: unknown): ConsentRequestKind {
  return value === CONSENT_REQUEST_KIND.memberFlag
    ? CONSENT_REQUEST_KIND.memberFlag
    : CONSENT_REQUEST_KIND.joinAdmission;
}

/**
 * The join-request row state while a guardian confirmation is outstanding. The captain
 * ANSWERED (so the 7-day unanswered sweep must not touch it) but admission has not
 * happened (so it is still a LIVE decision every liveness predicate must honor —
 * the FR-77 deletion veto, F-44 dedupe, and cross-family retirement all read it).
 * Old clients parse unknown statuses as `.pending` (fail-open display), which is
 * tolerable precisely because re-approve is idempotent.
 */
export const JOIN_REQUEST_AWAITING_GUARDIAN_STATUS = "awaiting_guardian";

/** Row statuses that mean "a decision about this child is still in flight". */
export const LIVE_JOIN_REQUEST_STATUSES: readonly string[] = [
  "pending",
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
];

// ---------------------------------------------------------------------------
// The "plus" notice (§3.1.2 step 4)
// ---------------------------------------------------------------------------

/**
 * FR-59.1: the second notice sent ≥24h after confirmation, carrying the revocation
 * path. It is what distinguishes email_plus (§312.5(b)(2)(viii)) from a bare email
 * click — REQUIRED for the method's lawfulness, not a courtesy. 24h is the floor;
 * the scheduler's cadence adds at most its own period on top.
 */
export const CONSENT_PLUS_NOTICE_DELAY_MS = 24 * 60 * 60 * 1000;

/**
 * Send-failure bound. Attempts are spaced by the scheduler's cadence, so this is
 * hours of retrying a transient outage, after which the request is marked abandoned
 * (loudly — an unsent plus notice is a lawfulness gap the FR-64 reconcile surfaces)
 * and the guardian's address is purged rather than retained indefinitely.
 */
export const CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS = 24;

/**
 * Dev knob (§3.1.2 checklist item 5): `CONSENT_PLUS_NOTICE_DELAY_MINUTES` in the
 * per-project functions `.env` file shortens the delay so the notice is testable
 * same-day. Anything unset/invalid/non-positive falls back to the 24h default —
 * production, whose env file never sets the knob, keeps the lawfulness floor.
 */
export function resolvePlusNoticeDelayMillis(override: string): number {
  const minutes = Number.parseInt(override, 10);
  if (Number.isInteger(minutes) && minutes > 0) return minutes * 60_000;
  return CONSENT_PLUS_NOTICE_DELAY_MS;
}

/**
 * Reconcile tripwire (§3.1.2 step 8): a confirmed request still unsent this long after
 * confirmation means the delivery job itself is broken (it aims for 24h–24h15m), not
 * merely slow. Knob-independent on purpose — with the dev knob set, notices send in
 * minutes and never come near this line.
 */
export const CONSENT_PLUS_NOTICE_OVERDUE_MS = 48 * 60 * 60 * 1000;

/**
 * Whether a consent-request document is due its plus notice. Confirmed requests only;
 * a sent or abandoned stamp is terminal. The status re-check is deliberate defense —
 * the caller's query already filters on it, but this predicate is the pinned truth.
 */
export function isPlusNoticeDue(
  data: {
    status?: unknown;
    confirmedAtMillis?: unknown;
    plusNoticeSentAtMillis?: unknown;
    plusNoticeAbandonedAtMillis?: unknown;
  },
  nowMillis: number,
  delayMillis: number
): boolean {
  if (data.status !== CONSENT_REQUEST_STATUS.confirmed) return false;
  if (typeof data.confirmedAtMillis !== "number") return false;
  if (data.plusNoticeSentAtMillis !== undefined) return false;
  if (data.plusNoticeAbandonedAtMillis !== undefined) return false;
  return data.confirmedAtMillis + delayMillis <= nowMillis;
}

// ---------------------------------------------------------------------------
// Nonce + confirmation token
// ---------------------------------------------------------------------------

export function mintConsentNonce(): string {
  return randomBytes(16).toString("hex");
}

export function hashConsentNonce(nonce: string): string {
  return createHash("sha256").update(nonce, "utf8").digest("hex");
}

/** Constant-time comparison of a presented nonce against the stored hash. */
export function consentNonceMatches(presentedNonce: string, storedHash: string): boolean {
  const presented = createHash("sha256").update(presentedNonce, "utf8").digest();
  const stored = Buffer.from(storedHash, "hex");
  return presented.length === stored.length && timingSafeEqual(presented, stored);
}

/** The emailed link's token: `<requestId>.<nonce>`, both URL-safe by construction. */
export function formatConsentToken(requestId: string, nonce: string): string {
  return `${requestId}.${nonce}`;
}

export function parseConsentToken(
  token: unknown
): { requestId: string; nonce: string } | null {
  if (typeof token !== "string" || token.length > 200) return null;
  const separator = token.indexOf(".");
  if (separator <= 0 || separator === token.length - 1) return null;
  const requestId = token.slice(0, separator);
  const nonce = token.slice(separator + 1);
  if (!/^[A-Za-z0-9]{1,40}$/.test(requestId) || !/^[a-f0-9]{32}$/.test(nonce)) return null;
  return { requestId, nonce };
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/**
 * FR-110 marker shape: `(birthYear + 13) * 100 + birthMonth`. Plausibility-bounded so a
 * corrupted client cannot stamp garbage the age-out machinery would later act on.
 */
export function isValidAgeOutYearMonth(value: unknown): value is number {
  if (typeof value !== "number" || !Number.isInteger(value)) return false;
  const month = value % 100;
  const year = Math.floor(value / 100);
  return month >= 1 && month <= 12 && year >= 1913 && year <= 2100;
}

export interface ConsentRequestDecisionInput {
  status: string;
  expiresAtMillis: number;
  attempts: number;
  nowMillis: number;
  presentedNonce: string;
  storedNonceHash: string;
}

export type ConsentRequestDecision =
  | { kind: "confirm" }
  | { kind: "already_confirmed" }
  | { kind: "expired" }
  | { kind: "refused" };

/**
 * The endpoint's whole gate as one pure function. Refusals are UNIFORM ("refused") for
 * wrong nonce, superseded requests, and attempt exhaustion — the link is a bearer
 * credential, and differentiated errors are an oracle (FR-24's discipline, applied to
 * the one surface that has no App Check).
 */
export function decideConsentConfirmation(
  input: ConsentRequestDecisionInput
): ConsentRequestDecision {
  if (input.attempts >= CONSENT_CONFIRM_MAX_ATTEMPTS) return { kind: "refused" };
  if (!consentNonceMatches(input.presentedNonce, input.storedNonceHash)) {
    return { kind: "refused" };
  }
  // A correct link is told the truth about its own request's state — the holder proved
  // possession, so state answers are not an oracle to them.
  if (input.status === CONSENT_REQUEST_STATUS.confirmed) return { kind: "already_confirmed" };
  if (input.status === CONSENT_REQUEST_STATUS.expired) return { kind: "expired" };
  if (input.status !== CONSENT_REQUEST_STATUS.pending) return { kind: "refused" };
  if (input.nowMillis > input.expiresAtMillis) return { kind: "expired" };
  return { kind: "confirm" };
}

// ---------------------------------------------------------------------------
// Consent-request email (NP-1 direct notice + confirmation link)
// ---------------------------------------------------------------------------

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export interface ConsentRequestEmailInput {
  /** Named `familyDisplayName` deliberately: the auditRedaction lint bans `familyName:` keys
   * source-wide to keep family names out of audit rows; this one goes into the NP-1 notice
   * email, which is meaningless without it, and never into an audit write. */
  familyDisplayName: string;
  childUserName: string;
  confirmUrl: string;
  envLabel: string;
  ttlHours: number;
  /** Which lifecycle the notice describes; the lede and the refusal consequence differ. */
  kind?: ConsentRequestKind;
}

/**
 * NP-1 direct notice, verbatim obligations (§312.4(c)(1)): what is collected, that the
 * parent's consent is required for collection/use, how to grant it, and that the child's
 * information is deleted if consent is not obtained. English at MVP; the ×3 localization
 * rides the NP-2 notice wave and is tracked there — this builder is the single place the
 * copy lives so that wave touches one function.
 */
export function buildConsentRequestEmailContent(
  input: ConsentRequestEmailInput
): { subject: string; html: string; text: string } {
  const family = escapeHtml(input.familyDisplayName);
  const child = escapeHtml(input.childUserName);
  const subjectPrefix = input.envLabel ? `[${input.envLabel}] ` : "";
  const isMemberFlag = input.kind === CONSENT_REQUEST_KIND.memberFlag;
  const subject = isMemberFlag
    ? `${subjectPrefix}Confirm your consent for ${input.childUserName} to continue in ${input.familyDisplayName} on RoadTrip Royale`
    : `${subjectPrefix}Confirm your consent for ${input.childUserName} to join ${input.familyDisplayName} on RoadTrip Royale`;

  const lede = isMemberFlag
    ? `You (or another manager of the "${input.familyDisplayName}" family) marked the family member "${input.childUserName}" in RoadTrip Royale as under 13. Their account is already protected; U.S. law (COPPA) requires your verifiable consent for them to continue playing as part of your family.`
    : `You (or another manager of the "${input.familyDisplayName}" family) approved a request from the player "${input.childUserName}" to join your family in RoadTrip Royale. Because this player indicated they are under 13, U.S. law (COPPA) requires your verifiable consent before their account becomes active.`;
  const refusalConsequence = isMemberFlag
    ? `If you do not consent, do nothing: the request expires and this player is removed from the family. Their account is kept, protected and paused, and they can rejoin later with your consent. You can withdraw consent at any time from Family settings in the app, which stops collection and lets you delete their data.`
    : `If you do not consent, do nothing: the request expires and the player's pending account information is deleted. You can withdraw consent at any time from Family settings in the app, which stops collection and lets you delete their data.`;

  const noticeText = [
    lede,
    ``,
    `What we collect if you consent: a nickname chosen in the app, a cartoon avatar selection, gameplay activity (license-plate finds, scores, trip participation), and an internal account identifier. We do not collect their real name, photos, contact information, or precise location, and there is no chat or messaging.`,
    `Who can see it: only members of your family group, which you control. Nothing is public, and children cannot be found or contacted by other users.`,
    `How it is used: to run the game and sync your family's shared trips. It is never used for advertising and never sold.`,
    ``,
    `To give your consent, open this link within ${input.ttlHours} hours:`,
    input.confirmUrl,
    ``,
    refusalConsequence,
  ].join("\n");

  const ledeHtml = isMemberFlag
    ? `<p>You (or another manager of the <strong>${family}</strong> family) marked the family member <strong>${child}</strong> in RoadTrip Royale as under 13. Their account is already protected; U.S. law (COPPA) requires your verifiable consent for them to continue playing as part of your family.</p>`
    : `<p>You (or another manager of the <strong>${family}</strong> family) approved a request from the player <strong>${child}</strong> to join your family in RoadTrip Royale. Because this player indicated they are under 13, U.S. law (COPPA) requires your verifiable consent before their account becomes active.</p>`;

  const html = [
    `<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1c1c1e;">`,
    `<h2 style="color:#1d4ed8;">Confirm your consent</h2>`,
    ledeHtml,
    `<p><strong>What we collect if you consent:</strong> a nickname chosen in the app, a cartoon avatar selection, gameplay activity (license-plate finds, scores, trip participation), and an internal account identifier. We do not collect their real name, photos, contact information, or precise location, and there is no chat or messaging.</p>`,
    `<p><strong>Who can see it:</strong> only members of your family group, which you control. Nothing is public, and children cannot be found or contacted by other users.</p>`,
    `<p><strong>How it is used:</strong> to run the game and sync your family's shared trips. It is never used for advertising and never sold.</p>`,
    `<p style="text-align:center;margin:32px 0;"><a href="${escapeHtml(input.confirmUrl)}" style="background:#1d4ed8;color:#ffffff;padding:12px 24px;border-radius:10px;text-decoration:none;font-weight:600;">I consent — activate this account</a></p>`,
    `<p style="font-size:13px;color:#6b7280;">This link works once and expires in ${input.ttlHours} hours. ${escapeHtml(refusalConsequence)}</p>`,
    `</div>`,
  ].join("");

  return { subject, html, text: noticeText };
}

// ---------------------------------------------------------------------------
// Confirmation endpoint: method routing + the GET interstitial
// ---------------------------------------------------------------------------

/**
 * Finding 2026-08-28 (live): mail security scanners and preview proxies follow GET
 * links automatically — observed as three valid-link hits in four seconds with no
 * human involved. A consent COMMIT on GET therefore lets a robot grant §312.5
 * consent while the request is pending. The commit moves to POST (scanners follow
 * links; they do not submit forms); GET serves a form and touches NOTHING — no doc
 * read, no attempt count, no state oracle.
 */
export type ConsentEndpointAction = "serve_form" | "process" | "method_not_allowed";

export function consentEndpointAction(method: unknown): ConsentEndpointAction {
  switch (typeof method === "string" ? method.toUpperCase() : "") {
    case "GET":
    case "HEAD":
      return "serve_form";
    case "POST":
      return "process";
    default:
      return "method_not_allowed";
  }
}

/**
 * The interstitial is deliberately GENERIC: it is served for any shape-valid token
 * WITHOUT verifying the nonce (verification costs an attempt and answers questions —
 * both belong to the POST), so it must not read the request document or name the
 * child or family. The guardian just read those names in the email that carried the
 * link; this page only asks for the human act the method requires.
 */
export function buildConsentInterstitialPage(input: {
  token: string;
  envLabel: string;
}): string {
  const prefix = input.envLabel ? `[${input.envLabel}] ` : "";
  return [
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${prefix}Confirm parental consent</title></head>`,
    `<body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:48px auto;padding:0 24px;color:#1c1c1e;">`,
    `<h2 style="color:#1d4ed8;">One more step</h2>`,
    `<p>You followed a parental-consent link from a RoadTrip Royale email. To confirm your consent and activate the player's account, press the button below.</p>`,
    `<form method="post"><input type="hidden" name="t" value="${escapeHtml(input.token)}">`,
    `<button type="submit" style="background:#1d4ed8;color:#ffffff;padding:12px 24px;border-radius:10px;border:none;font-size:16px;font-weight:600;cursor:pointer;">I consent — activate this account</button>`,
    `</form>`,
    `<p style="font-size:13px;color:#6b7280;margin-top:24px;">Nothing happens without the button. If you did not expect this page, you can simply close it.</p>`,
    `</body></html>`,
  ].join("");
}

// ---------------------------------------------------------------------------
// The "plus" notice email (delayed confirmation + revocation path)
// ---------------------------------------------------------------------------

export interface ConsentPlusNoticeEmailInput {
  /** See `ConsentRequestEmailInput.familyDisplayName` for the naming rationale. */
  familyDisplayName: string;
  childUserName: string;
  envLabel: string;
}

/**
 * The §312.5(b)(2)(viii) delayed confirmatory notice: a record of the consent the
 * guardian gave, and the standing path to withdraw it (Family settings in the app).
 * Deliberately dateless — the guardian's local date can differ from any timestamp we
 * would print, and "recently" is the truthful framing at every delay setting. English
 * at MVP, same as the NP-1 builder; localization rides the NP-2 wave.
 */
export function buildConsentPlusNoticeEmailContent(
  input: ConsentPlusNoticeEmailInput
): { subject: string; html: string; text: string } {
  const family = escapeHtml(input.familyDisplayName);
  const child = escapeHtml(input.childUserName);
  const subjectPrefix = input.envLabel ? `[${input.envLabel}] ` : "";
  const subject = `${subjectPrefix}Your consent for ${input.childUserName} on RoadTrip Royale — and how to withdraw it`;

  const text = [
    `This is a follow-up to the consent you recently confirmed for the player "${input.childUserName}" in the "${input.familyDisplayName}" family on RoadTrip Royale. U.S. law (COPPA) requires this second notice so you have a record of that consent and a way to change your mind.`,
    ``,
    `What you consented to: the app collects this player's chosen nickname, cartoon avatar selection, gameplay activity (license-plate finds, scores, trip participation), and an internal account identifier — visible only to members of your family group, which you control. Nothing is public, there is no chat or messaging, and their information is never used for advertising and never sold.`,
    ``,
    `To withdraw consent at any time: open RoadTrip Royale and go to Family settings. Withdrawing stops collection and lets you delete the player's data.`,
    ``,
    `If you did not confirm this consent, open Family settings and remove the player from your family — that withdraws the consent and stops collection immediately.`,
  ].join("\n");

  const html = [
    `<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1c1c1e;">`,
    `<h2 style="color:#1d4ed8;">A record of your consent</h2>`,
    `<p>This is a follow-up to the consent you recently confirmed for the player <strong>${child}</strong> in the <strong>${family}</strong> family on RoadTrip Royale. U.S. law (COPPA) requires this second notice so you have a record of that consent and a way to change your mind.</p>`,
    `<p><strong>What you consented to:</strong> the app collects this player's chosen nickname, cartoon avatar selection, gameplay activity (license-plate finds, scores, trip participation), and an internal account identifier — visible only to members of your family group, which you control. Nothing is public, there is no chat or messaging, and their information is never used for advertising and never sold.</p>`,
    `<p><strong>To withdraw consent at any time:</strong> open RoadTrip Royale and go to Family settings. Withdrawing stops collection and lets you delete the player's data.</p>`,
    `<p style="font-size:13px;color:#6b7280;">If you did not confirm this consent, open Family settings and remove the player from your family — that withdraws the consent and stops collection immediately.</p>`,
    `</div>`,
  ].join("");

  return { subject, html, text };
}
