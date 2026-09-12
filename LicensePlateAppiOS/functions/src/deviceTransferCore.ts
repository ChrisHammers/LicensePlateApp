/**
 * Parent-initiated device transfer — pure policy core (COPPA v3 FR-84 / F-41).
 *
 * A consented child holds an anonymous, keychain-backed account with no credentials
 * (FR-60(c) defers credentials to a parent-managed follow-up). A new device therefore
 * strands the account, its XP, achievements and trip history permanently. FR-84's fix is a
 * guardian-issued, single-use, short-lived code that rebinds the EXISTING child account to
 * a new device — without ever putting credentials in the child's hands, and without a new
 * consent round (the account is already consented).
 *
 * Everything here is data-in / decision-out so the whole matrix is unit-testable with no
 * Firestore stand-in at all (same shape as `inviteRateLimitCore.ts` / `retentionCore.ts`).
 * The Firestore + Auth wiring lives in `deviceTransfer.ts`.
 *
 * WHY A SEPARATE COLLECTION RATHER THAN A THIRD `share_codes` TYPE
 * ---------------------------------------------------------------
 * FR-84's text says "reuses the existing share-code machinery (new `type`)". The redemption
 * *shape* is reused — short TTL, single resolver callable, `share_redeem` throttle — but the
 * rows deliberately do NOT live in `share_codes`, for three reasons that are all security,
 * not taste:
 *
 *  1. `share_codes` is READABLE by every member of the named family
 *     (`shareCodeIsReadableBySelf`, FR-67). A transfer code is a bearer credential for one
 *     specific child's ACCOUNT — a sibling reading it off the collection would be exactly
 *     FR-84 future-item (iii)'s "child-to-child account-sharing vector", handed out by the
 *     rules themselves.
 *  2. `share_codes` permits client `create`/`update` by any registered non-child. A transfer
 *     row there would be mintable by direct Firestore write, bypassing the FR-62
 *     guardianship ladder entirely, unless the rules grew a deny-by-exception on a `type`
 *     string — a fragile shape where the safe default is the one that must be spelled out.
 *  3. Redeeming a `share_codes` row mints an INVITE. Transfer mints an auth credential.
 *     Overloading one callable with two outcomes of such different weight is how the wrong
 *     branch eventually runs.
 *
 * `device_transfer_codes` is therefore server-written-only, get-by-id for its creator, and
 * never listable. See the `firestore.rules` block.
 */

/** Root collection holding one document per issued transfer code. */
export const DEVICE_TRANSFER_CODE_COLLECTION = "device_transfer_codes";

/**
 * TTL, matching `createShareCode`'s 15 minutes.
 *
 * Sized for the flow it actually serves: the guardian is next to the child, reading the code
 * off their own screen onto the new device. FR-84 asks for a "short TTL"; 15 minutes is the
 * house value and leaves room for one "let me type that again", while a bearer credential
 * for a child's account stays live for a quarter hour rather than a day.
 */
export const DEVICE_TRANSFER_CODE_TTL_MS = 15 * 60 * 1000;

/** Same alphabet and length as `generateRandomCode` in `shareCodes.ts` — read-aloud parity. */
export const DEVICE_TRANSFER_CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
export const DEVICE_TRANSFER_CODE_LENGTH = 6;

/**
 * Audit event types. Deliberately NOT added to `CHILD_CONSENT_EVENT_TYPES`.
 *
 * FR-84 future-item (iv) is explicit: a transferred account keeps its guardianship record
 * (FR-62) and its post-revocation retention window (FR-77) — **transfer is not a consent
 * event and must not reset either**. `CHILD_CONSENT_EVENT_TYPES` is what
 * `familyChildStatusFlows.ts` reads to reconstruct a child's consent history and what FR-64's
 * nightly reconcile scores for assurance level; a transfer row appearing in that set would
 * make a device swap look like a consent capture. These rows are lifecycle evidence, read by
 * humans, and nothing else keys off them.
 */
export const AUDIT_CHILD_DEVICE_TRANSFER_ISSUED = "AUDIT_CHILD_DEVICE_TRANSFER_ISSUED";
export const AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED = "AUDIT_CHILD_DEVICE_TRANSFER_REDEEMED";

/**
 * The ONE reply every redemption failure produces (FR-24 indistinguishability, applied
 * harder here than `redeemShareCode` applies it).
 *
 * `redeemShareCode` distinguishes not-found (`not-found`) from expired (`invalid-argument`).
 * That is tolerable for an invite code. It is not tolerable here: a transfer code names a
 * specific child account, so a caller who could tell "no such code" from "that code is spent"
 * from "that child is no longer consented" could probe the code space AND learn facts about
 * a named child's consent state from the reply shape. Every negative outcome below —
 * unknown code, expired, revoked, already redeemed, superseded, target no longer eligible —
 * throws this exact error with NO `details` payload, since `details` is the same channel by
 * another name. `deviceTransfer.test.ts` pins the outcomes against each other field by field.
 */
export const DEVICE_TRANSFER_UNAVAILABLE_MESSAGE =
  "That transfer code is not available. Ask a parent for a new one.";

/**
 * The server could not sign the child's credential — an OPERATIONAL failure (the Cloud
 * Functions runtime service account lacks `roles/iam.serviceAccountTokenCreator`, owner device
 * test 2026-09-10), never something the parent did. Distinct from the FR-24 refusal on
 * purpose: it names no child fact, and the code is deliberately left LIVE so the same code
 * works once the server is fixed.
 */
export const DEVICE_TRANSFER_SIGNING_FAILED_MESSAGE =
  "Transfers aren't working right now. Nothing was changed — please try again later.";

/** Uppercase-normalize, matching `redeemShareCode`'s tolerance for a lowercase entry. */
export function normalizeDeviceTransferCode(code: unknown): string | null {
  if (typeof code !== "string") return null;
  const trimmed = code.trim().toUpperCase();
  return trimmed.length === 0 ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Eligibility of the TARGET child
// ---------------------------------------------------------------------------

/**
 * FR-84: a code may be minted only "for a child currently consented in that family", and the
 * same must still hold at REDEMPTION time — a revocation between mint and redemption has to
 * void a live code.
 *
 * Deliberately stricter than `authorizeParentalRights`, which (FR-62) also admits the
 * recorded guardian of an ALREADY-REMOVED child so their §312.6 review/deletion rights
 * survive. Those are rights over data; this is re-homing a live playing session. A revoked
 * child sits in the FR-28 restricted state waiting out FR-77's window, and moving that
 * account onto a fresh device is not something the requirement asks for.
 *
 * `activeFamilyId` alone is never trusted — it is client-writable on one's own user doc
 * (see the `firestore.rules` note on `callerIsConsentedChildMemberOf`). The caller pairs
 * this with a member-doc `exists()`, which is server-written only (FR-8).
 */
export function isTransferEligibleChildUserData(
  userData: Record<string, unknown> | undefined,
  familyId: string
): boolean {
  if (!userData) return false;
  if (userData.isChildAccount !== true) return false;
  return typeof userData.activeFamilyId === "string" && userData.activeFamilyId === familyId;
}

// ---------------------------------------------------------------------------
// Redemption decision
// ---------------------------------------------------------------------------

export interface DeviceTransferCodeRecord {
  code?: unknown;
  childUserId?: unknown;
  familyId?: unknown;
  createdBy?: unknown;
  expiresAtMillis?: unknown;
  isRevoked?: unknown;
  redeemedAtMillis?: unknown;
}

export type DeviceTransferRedemptionRefusal =
  | "not_found"
  | "malformed"
  | "expired"
  | "revoked"
  | "already_redeemed";

export type DeviceTransferRedemptionDecision =
  | { claimable: true; childUserId: string; familyId: string }
  | { claimable: false; refusal: DeviceTransferRedemptionRefusal };

/**
 * Decide whether a resolved code row may still be claimed.
 *
 * The `refusal` discriminant exists for TESTS and server logs only — every branch produces
 * the same `DEVICE_TRANSFER_UNAVAILABLE_MESSAGE` at the callable boundary. Keeping the reason
 * as a value here, rather than as differing throw sites, is what makes the
 * indistinguishability assertable instead of merely intended.
 *
 * An unreadable `expiresAtMillis` counts as EXPIRED, matching `redeemShareCode`: a bearer
 * credential whose TTL cannot be established must not be honoured indefinitely.
 */
export function evaluateDeviceTransferRedemption(
  record: DeviceTransferCodeRecord | undefined,
  nowMs: number
): DeviceTransferRedemptionDecision {
  if (!record) return { claimable: false, refusal: "not_found" };

  const childUserId = record.childUserId;
  const familyId = record.familyId;
  if (
    typeof childUserId !== "string" ||
    childUserId.length === 0 ||
    typeof familyId !== "string" ||
    familyId.length === 0
  ) {
    return { claimable: false, refusal: "malformed" };
  }

  if (record.isRevoked === true) return { claimable: false, refusal: "revoked" };
  if (record.redeemedAtMillis !== undefined && record.redeemedAtMillis !== null) {
    return { claimable: false, refusal: "already_redeemed" };
  }

  const expiresAtMillis = record.expiresAtMillis;
  if (typeof expiresAtMillis !== "number" || !Number.isFinite(expiresAtMillis)) {
    return { claimable: false, refusal: "expired" };
  }
  if (expiresAtMillis <= nowMs) return { claimable: false, refusal: "expired" };

  return { claimable: true, childUserId, familyId };
}

// ---------------------------------------------------------------------------
// Audit metadata (uid-only — `childConsent.ts`'s `assertUidOnly` runs over these)
// ---------------------------------------------------------------------------

export function buildDeviceTransferIssuedMetadata(input: {
  childUserId: string;
  familyId: string;
  actorRole: string;
  codeId: string;
  supersededCodeCount: number;
}): Record<string, unknown> {
  return {
    childUserId: input.childUserId,
    familyId: input.familyId,
    actorRole: input.actorRole,
    codeId: input.codeId,
    supersededCodeCount: input.supersededCodeCount,
    method: "parent_issued_code",
  };
}

export function buildDeviceTransferRedeemedMetadata(input: {
  childUserId: string;
  familyId: string;
  codeId: string;
  /** The uid that made the call — the new device's throwaway session, or an adult's. */
  redeemedByUserId: string;
  /** Whether the redeeming session's provisional child account was cleaned up. */
  discardedProvisionalAccount: boolean;
}): Record<string, unknown> {
  return {
    childUserId: input.childUserId,
    familyId: input.familyId,
    codeId: input.codeId,
    redeemedByUserId: input.redeemedByUserId,
    discardedProvisionalAccount: input.discardedProvisionalAccount,
    method: "parent_issued_code",
  };
}

// ---------------------------------------------------------------------------
// Cleanup of the redeeming session's provisional account
// ---------------------------------------------------------------------------

/**
 * FR-60 / FR-77 residue: may the uid that made the redemption call be discarded?
 *
 * The new device reaches this callable the same way FR-60 has every declared child reach a
 * consent exit — mint an anonymous uid, bind it, declare it, then call. For a family join
 * that provisional uid BECOMES the consented child. For a transfer it is throwaway: the real
 * account already exists and the device is about to sign in as it, so the provisional row is
 * pure residue of the "redemption-window accounts" class FR-77 already sweeps at 7 days.
 * Deleting it inline is the same courtesy FR-60(c)'s decline path performs; the sweep remains
 * the backstop, so this is belt-and-braces and is called best-effort.
 *
 * Every clause is a refusal to touch an account that might be somebody's:
 *  - never the transfer TARGET (that is the account being kept);
 *  - only a declared child (an adult's own account is never collateral of their child's
 *    device setup — a parent who sets the new device up from their own session keeps it);
 *  - only an UNCONSENTED one (no `activeFamilyId`): a consented child's account is a live,
 *    parent-approved account and deleting it would destroy exactly the history FR-84 exists
 *    to preserve, for the wrong child.
 */
export function mayDiscardRedeemingProvisionalAccount(input: {
  redeemerUserId: string;
  targetChildUserId: string;
  redeemerUserData: Record<string, unknown> | undefined;
}): boolean {
  if (input.redeemerUserId === input.targetChildUserId) return false;
  const data = input.redeemerUserData;
  if (!data) return false;
  if (data.isChildAccount !== true) return false;
  const activeFamilyId = data.activeFamilyId;
  return typeof activeFamilyId !== "string" || activeFamilyId.length === 0;
}
