/**
 * Join-request lineage and new-guardian seasoning — COPPA FR-66 (F-22).
 *
 * WHAT THIS CLOSES
 * ----------------
 * Family membership IS the parental-consent object in this app: `activeFamilyId` is the
 * consent proxy (`isUnconsentedChildUserData`), and a family creator/captain is the
 * "parent/manager" every child rule defers to. That made the boundary forgeable, because
 * nothing tied a `families/{id}/pending/*` row to an invitation anyone had actually issued:
 *
 *   1. a child mints a throwaway "adult" account and calls `createFamily` — they are now a
 *      captain, i.e. their own consenting manager;
 *   2. from their REAL (flagged) account they write a pending join request naming that
 *      family directly — target familyIds are harvestable because `activeFamilyId` sits on
 *      the peer-readable user doc;
 *   3. the throwaway captain approves it with `isChild: false`, and every COPPA protection
 *      on the real account drops.
 *
 * FR-66 breaks that at two independent links, and this module holds both.
 *
 * LINEAGE (FR-66a)
 * ----------------
 * `firestore.rules` closes client creation of `pending/*` outright (`create: if false` —
 * verified zero-regression: the shipped client only ever READS the subcollection, via a
 * snapshot listener and a status-filtered query in `FamilyRepository`). Pending rows are
 * now minted only by `respondToFamilyInvite_UserStep`, which stamps the `invites` document
 * that authorised them — and, when that invite was itself minted by `redeemShareCode`, the
 * share code behind it. `invites` has been server-only since FR-16(a), so the stamp chains
 * back to a document no client could have forged. `approveFamilyJoinRequest_CaptainStep`
 * refuses to approve a row without one, which kills step 2 above even if a rules
 * misconfiguration ever re-opened the write.
 *
 * SEASONING (FR-66b)
 * ------------------
 * Lineage alone does not stop the laundering chain — the child could redeem a code from
 * their own throwaway family and arrive with a perfectly good stamp. So clearing a sticky
 * child flag through approval additionally requires that the approving family look like a
 * real family rather than one conjured to launder a flag: it must either predate the join
 * request by more than the OD-5 window (72h), or already contain an adult who is neither
 * the approver nor the person being approved. A family spun up minutes ago with exactly one
 * adult in it — the attacker — satisfies neither.
 *
 * The two arms are deliberately OR'd. Requiring both would brick the legitimate case this
 * exists to permit: a genuine new guardian who creates a family today and re-admits a child
 * whose flag was set in error simply waits out the window, and a two-parent family is
 * unaffected from day one.
 *
 * Db-parameterized like `inviteRelationshipGate.ts` / `childAccessGuards.ts`, so both gates
 * are exercisable end to end against `testSupport/fakeFirestore.ts`.
 */

import * as functions from "firebase-functions/v1";
import type * as admin from "firebase-admin";
import { LIVE_JOIN_REQUEST_STATUSES } from "./consentRequestsCore";

type Firestore = admin.firestore.Firestore;

// ---------------------------------------------------------------------------
// FR-66(a) — join-request lineage
// ---------------------------------------------------------------------------

/** How a pending join request came to exist. Both values are minted server-side only. */
export const JOIN_REQUEST_ORIGINS = ["share_code", "family_invite"] as const;

export type JoinRequestOrigin = (typeof JOIN_REQUEST_ORIGINS)[number];

export interface JoinRequestLineage {
  origin: JoinRequestOrigin;
  /** The `invites/{id}` document that authorised this request. Always present. */
  originInviteId: string;
  /** The `share_codes/{id}` the invite was redeemed from, when there was one. */
  originCodeId?: string;
}

/**
 * Build the stamp for a request `respondToFamilyInvite_UserStep` is about to write.
 *
 * `codeId` is present exactly when `redeemShareCode` minted the invite, so it is what
 * distinguishes the two origins — there is no separate flag to keep in sync.
 */
export function buildJoinRequestLineage(input: {
  inviteId: string;
  codeId?: unknown;
}): JoinRequestLineage {
  const codeId =
    typeof input.codeId === "string" && input.codeId.length > 0 ? input.codeId : undefined;
  const lineage: JoinRequestLineage = {
    origin: codeId ? "share_code" : "family_invite",
    originInviteId: input.inviteId,
  };
  if (codeId) {
    lineage.originCodeId = codeId;
  }
  return lineage;
}

/** Parse a stored stamp. Anything missing or malformed reads as "no lineage". */
export function readJoinRequestLineage(
  data: Record<string, unknown> | undefined | null
): JoinRequestLineage | null {
  if (!data) return null;
  const origin = data.origin;
  const originInviteId = data.originInviteId;
  if (typeof origin !== "string" || !JOIN_REQUEST_ORIGINS.includes(origin as JoinRequestOrigin)) {
    return null;
  }
  if (typeof originInviteId !== "string" || originInviteId.length === 0) {
    return null;
  }
  const lineage: JoinRequestLineage = {
    origin: origin as JoinRequestOrigin,
    originInviteId,
  };
  if (typeof data.originCodeId === "string" && data.originCodeId.length > 0) {
    lineage.originCodeId = data.originCodeId;
  }
  return lineage;
}

export const JOIN_REQUEST_LINEAGE_MISSING_MESSAGE =
  "This join request did not come from an invite and cannot be approved";

/**
 * FR-66(a): refuse to approve a pending row that no invite produced.
 *
 * Applied on the APPROVE branch only. Decline stays open so a manager can always clear a
 * stale or malformed row out of their queue — a request that cannot be approved and cannot
 * be dismissed would be exactly the unrecoverable state §2.4 asks us to check for.
 */
export function assertJoinRequestLineage(
  data: Record<string, unknown> | undefined | null
): JoinRequestLineage {
  const lineage = readJoinRequestLineage(data);
  if (lineage === null) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      JOIN_REQUEST_LINEAGE_MISSING_MESSAGE
    );
  }
  return lineage;
}

// ---------------------------------------------------------------------------
// F-44 — one live join request per (family, user)
// ---------------------------------------------------------------------------

/**
 * The only status a `families/{id}/pending` row holds while it awaits a captain's decision.
 * `FamilyRepository.fetchPendingRequests` filters on exactly this string, and
 * `PendingJoinRequest(from:)` REFUSES to parse a status outside its four-case enum
 * (`pending` / `approved` / `declined` / `expired`) — a row wearing anything else is dropped
 * client-side and never updates the cached copy, which would strand it in the captain's
 * queue forever. Every status this module writes therefore comes from that enum.
 */
export const JOIN_REQUEST_PENDING_STATUS = "pending";

/**
 * Terminal status for a duplicate row retired ALONGSIDE the row that actually carried the
 * decision. "expired" for the same reason `family.ts` retires superseded invites with it
 * rather than a new word: it is inside the client's enum, and it is terminal — "declined"
 * would tell the requester their consent was refused when in fact it was granted on the
 * sibling row.
 */
export const JOIN_REQUEST_SUPERSEDED_STATUS = "expired";

/**
 * Every still-undecided join request `userId` holds in `familyId`, newest-agnostic and
 * id-ordered, optionally minus the one the caller is already holding.
 *
 * Device pass 2026-08-16: redeeming one family share code twice minted two invites, two
 * accepts, and two indistinguishable "Pending User" rows for a single child. Resolving one
 * of them ran FR-60(c)'s never-consented cleanup and DELETED the account — leaving the other
 * row pointing at a uid that no longer exists, unapprovable ("User not found") for good.
 * Both halves of that are fixed by never letting the second row exist and by resolving any
 * that do in the same operation; this query is what both halves are built on.
 *
 * Two equality filters on a subcollection — served by the automatic single-field indexes, the
 * same shape `family.ts` already uses against `invites`.
 */
export async function findLivePendingJoinRequests(
  db: Firestore,
  input: { familyId: string; userId: string; excludeRequestId?: string }
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  // FR-59.1 (2026-08-27): a row awaiting guardian confirmation is LIVE — a second
  // redemption must dedupe against it, never mint a rival beside it. Two queries
  // (no `in` support in the test harness); order pending-first for stable results.
  const snapshots = await Promise.all(
    LIVE_JOIN_REQUEST_STATUSES.map((status) =>
      db
        .collection(`families/${input.familyId}/pending`)
        .where("userId", "==", input.userId)
        .where("status", "==", status)
        .limit(20)
        .get()
    )
  );
  return snapshots
    .flatMap((snapshot) => snapshot.docs)
    .filter((doc) => doc.id !== input.excludeRequestId);
}

// ---------------------------------------------------------------------------
// The boundary was never the family — it was the user (owner decision 2026-08-17)
// ---------------------------------------------------------------------------

/**
 * How many other-family rows one decision may look at. Twenty is far past reachable: F-44
 * holds a user to ONE live row per family, so this bound is only ever met by legacy or
 * adversarial data. Exceeded, it is REPORTED rather than swallowed (`truncated`) — the caller
 * logs, and `sweepUnansweredJoinRequests` retires whatever was left behind on its own clock.
 */
export const CROSS_FAMILY_JOIN_REQUEST_LIMIT = 20;

export interface CrossFamilyJoinRequests {
  rows: admin.firestore.QueryDocumentSnapshot[];
  /** True when the read bound may have hidden further rows. Never silently. */
  truncated: boolean;
}

/**
 * `families/{familyId}/pending/{requestId}` -> `familyId`. The row does not carry its own
 * family, so the path is the only source; a collection-group query is the only reader that
 * needs it.
 */
export function pendingRowFamilyId(
  doc: admin.firestore.DocumentSnapshot | admin.firestore.QueryDocumentSnapshot
): string | null {
  return doc.ref.parent.parent?.id ?? null;
}

/**
 * Every still-undecided join request `userId` holds OUTSIDE `excludeFamilyId`.
 *
 * A user has exactly one `activeFamilyId`. The instant one family admits them, every live row
 * they hold in another family is unapprovable — `canAddMemberToFamily` answers "User is
 * already in another active family", and FR-15 refuses even to invite a child who has one —
 * yet the row still renders as an ordinary pending request. Another captain affirms
 * guardianship over it, taps approve, and gets a failure for a decision that could never have
 * succeeded. `findLivePendingJoinRequests` above closes exactly this inside one family; the
 * query below is the same question asked across all of them.
 *
 * Served by the `pending (COLLECTION_GROUP): userId ASC, status ASC` composite index that
 * `hasLiveJoinRequest` already needs — two equality filters, no new index.
 *
 * The approving family is filtered out AFTER the read rather than excluded in the query
 * (Firestore has no "not this parent" filter), so a caller whose own family holds more than
 * the bound in duplicate rows can come back `truncated` with rows it never saw. That is the
 * honest failure: it logs, and the unanswered-row sweep is the backstop.
 */
export async function findLivePendingJoinRequestsInOtherFamilies(
  db: Firestore,
  input: { userId: string; excludeFamilyId: string; limit?: number }
): Promise<CrossFamilyJoinRequests> {
  const limit = input.limit ?? CROSS_FAMILY_JOIN_REQUEST_LIMIT;
  // FR-59.1 (2026-08-27): both live statuses (`pending`, `awaiting_guardian`) — another
  // family's outstanding guardian confirmation is a live decision this retirement must
  // resolve too, or the losing family's email link would race the winner's forever.
  const snapshots = await Promise.all(
    LIVE_JOIN_REQUEST_STATUSES.map((status) =>
      db
        .collectionGroup("pending")
        .where("userId", "==", input.userId)
        .where("status", "==", status)
        // One past the bound, so "there were more" is distinguishable from "that was all".
        .limit(limit + 1)
        .get()
    )
  );
  const totalSeen = snapshots.reduce((sum, snapshot) => sum + snapshot.size, 0);
  const rows = snapshots
    .flatMap((snapshot) => snapshot.docs)
    .filter((doc) => pendingRowFamilyId(doc) !== input.excludeFamilyId);
  return { rows: rows.slice(0, limit), truncated: totalSeen > limit };
}

// ---------------------------------------------------------------------------
// FR-86 (F-43) — the guardian can tell which child they are approving
// ---------------------------------------------------------------------------

/**
 * FR-86: the ONLY fields the pending row may carry about the requester.
 *
 * A pending row used to hold `userId`, `status`, `createdAt` and the FR-66 lineage stamp and
 * nothing else, while FR-12 denies peer reads of a non-member child's user doc — so a captain
 * approving saw a raw uid, and FR-31's affirmation ("I confirm I am THIS CHILD's parent or
 * legal guardian") cannot truthfully be made about one. With two children pending they are
 * indistinguishable, and approving the wrong one produces a consent artifact naming child A
 * under an affirmation the guardian believed concerned child B.
 *
 * The list is exhaustive and the builder below reads NOTHING else off the user doc: FR-86's
 * first constraint is username and avatar only, never email, phone, or anything from
 * `private/contact`. §312.5(c)(1) covers exactly this use — the child's name, for the sole
 * purpose of obtaining parental consent — and its deletion condition is already discharged by
 * FR-60(c)'s decline/expiry account deletion. Widening this array would step outside that
 * exception, so it is pinned by test.
 */
export const PENDING_REQUEST_IDENTITY_FIELDS = ["userName", "avatarId"] as const;

export type PendingRequestIdentity = Partial<
  Record<(typeof PENDING_REQUEST_IDENTITY_FIELDS)[number], string>
>;

/**
 * Pick the FR-86 fields out of a user doc. Absent or non-string values are simply omitted.
 *
 * The caller reads the user doc through the Admin SDK, which is the whole point: the captain
 * cannot make that read themselves (FR-12), and `families/{id}/pending` is already
 * family-readable, so stamping it server-side needs no rules change.
 */
export function buildPendingRequestIdentity(
  userData: Record<string, unknown> | undefined | null
): PendingRequestIdentity {
  const identity: PendingRequestIdentity = {};
  for (const field of PENDING_REQUEST_IDENTITY_FIELDS) {
    const value = userData?.[field];
    if (typeof value === "string" && value.length > 0) {
      identity[field] = value;
    }
  }
  return identity;
}

// ---------------------------------------------------------------------------
// FR-88 (F-45) — the child can tell whether anyone is actually deciding
// ---------------------------------------------------------------------------

/**
 * Server-owned mirror of "a family is deciding about me", written onto the ONE document a
 * child can always read: their own `users/{uid}`.
 *
 * Device pass 2026-08-17. "Waiting for your family's approval" was a pure device guess — a
 * UserDefaults uid written at share-code redemption, cleared in exactly two places (the child
 * stops being restricted, i.e. they were approved; and identity detach, i.e. the account was
 * deleted). A DECLINE that does not delete the account clears neither, and FR-60(c)
 * deliberately skips deletion for a child with `wasEverInFamily === true`. That child kept
 * claiming a captain was deciding, forever, with no way to check: `firestore.rules` restricts
 * `families/{id}/pending` reads to family members, and a pending child is by definition not
 * one.
 *
 * So the truth is pushed to where they can see it. PRESENCE of this field is the whole
 * signal; the payload is for debugging and for a future "which family?" surface, never for a
 * rule decision. The field is listed in the rules' server-controlled key guard alongside
 * `childDeclaredAt`, so a client can neither forge it nor clear it.
 *
 * SCOPE — written only for an UNCONSENTED CHILD (`isUnconsentedChildUserData`), which is the
 * exact population the FR-28 surfaces it drives exist for. An adult accepting a family invite
 * gets no stamp: `ChildFamilyPromptPolicy` resolves pending BEFORE its restriction
 * classification, so a stamp on an adult's doc would raise the "ask a parent" banner on an
 * adult's home screen. A consented child joining a second family is excluded for the same
 * reason — their banner is hidden today and must stay hidden.
 *
 * CLEARING is deliberately NOT scoped: a resolution clears the field whoever holds it, so it
 * can only ever fail toward "nobody is deciding". A false negative costs a child a status line
 * they can refresh by re-entering a code (FR-28f keeps that reachable from every pending
 * presentation); a false positive is the unrecoverable state this exists to kill.
 *
 * ONE STAMP PER USER used to make that failure routine, and owner decision 2026-08-17 removed
 * the routine case rather than living with it. A child with live rows in two families carries
 * a single stamp, so resolving one row cleared it while the other was still live. Now:
 *
 *   - APPROVE retires every live row the admitted user holds in EVERY OTHER family, in the
 *     same batch as the grant (`approveFamilyJoinRequest_CaptainStep`). Those rows were
 *     already unapprovable — one `activeFamilyId` per user — so the single clear is exactly
 *     true afterwards, and a second clear would be an illegal duplicate write to one document.
 *   - DECLINE retires nothing elsewhere: refusing consent in family A says nothing about
 *     family B, whose request is still legitimate. It RE-POINTS the stamp at a surviving row
 *     instead of clearing it, so the child's "waiting" state survives the decline that was
 *     never about it.
 *
 * Two unconditional clears remain and stay accepted: the unanswered-row sweep
 * (`pendingJoinRequestExpiry.ts`) and `inactivateFamily`. Each retires rows in ONE family
 * without re-pointing, so a child holding a live row elsewhere can still lose the status line
 * early — the tolerable direction, and recoverable by re-entering a code.
 */
export const PENDING_FAMILY_REQUEST_FIELD = "pendingFamilyRequest";

export interface PendingFamilyRequestStamp {
  familyId: string;
  requestId: string;
  /** `FieldValue.serverTimestamp()` at the call site — the client never reads the value. */
  createdAt: unknown;
}

/**
 * Build the stamp for the row `respondToFamilyInvite_UserStep` is about to write. Shaped as a
 * builder for the same reason `buildJoinRequestLineage` is: one definition of the payload, so
 * the stamp and the row it mirrors cannot drift apart across the two branches that write it.
 */
export function buildPendingFamilyRequestStamp(input: {
  familyId: string;
  requestId: string;
  createdAt: unknown;
}): PendingFamilyRequestStamp {
  return {
    familyId: input.familyId,
    requestId: input.requestId,
    createdAt: input.createdAt,
  };
}

// ---------------------------------------------------------------------------
// FR-66(b) — new-guardian seasoning
// ---------------------------------------------------------------------------

/** OD-5: how far a family must predate a join request to clear a flag on its own. */
export const GUARDIAN_CLEAR_SEASONING_WINDOW_MS = 72 * 60 * 60 * 1000;

export const GUARDIAN_CLEAR_SEASONING_MESSAGE =
  "This family is too new to change a member's child status. Another adult in the family " +
  "can approve instead, or try again once the family is older.";

/**
 * Firestore `Timestamp` | `Date` | epoch millis -> millis. Anything else (notably a
 * `FieldValue.serverTimestamp()` sentinel that has not resolved yet) reads as unknown.
 */
export function timestampToMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  const candidate = value as { toMillis?: () => number; toDate?: () => Date } | null;
  if (candidate && typeof candidate.toMillis === "function") {
    const millis = candidate.toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  if (candidate && typeof candidate.toDate === "function") {
    const date = candidate.toDate();
    const millis = date instanceof Date ? date.getTime() : NaN;
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

export interface GuardianClearSeasoningInput {
  familyCreatedAtMs: number | null;
  requestCreatedAtMs: number | null;
  /** Adults in the family who are neither the approver nor the member being approved. */
  otherAdultMemberCount: number;
}

/**
 * FR-66(b): may this family clear a sticky child flag through approval?
 *
 * Unreadable timestamps fail the age arm rather than passing it — a corrupt or unresolved
 * `createdAt` must never be the thing that unlocks a flag clear. The corroborating-adult arm
 * still applies, so a real family is never stuck.
 */
export function evaluateGuardianClearSeasoning(
  input: GuardianClearSeasoningInput,
  windowMs: number = GUARDIAN_CLEAR_SEASONING_WINDOW_MS
): { ok: boolean; reason: "corroborating_adult" | "family_seasoned" | "denied" } {
  if (input.otherAdultMemberCount >= 1) {
    return { ok: true, reason: "corroborating_adult" };
  }
  const { familyCreatedAtMs, requestCreatedAtMs } = input;
  if (
    familyCreatedAtMs !== null &&
    requestCreatedAtMs !== null &&
    requestCreatedAtMs - familyCreatedAtMs > windowMs
  ) {
    return { ok: true, reason: "family_seasoned" };
  }
  return { ok: false, reason: "denied" };
}

/**
 * Count adults in `families/{familyId}/members` other than the approver and the target.
 *
 * `isChild` on a member doc is the server-written projection (§7.2, FR-8 keeps it
 * client-unwritable), and a missing flag means adult (§4) — consistent with every other
 * child predicate in the codebase.
 */
export async function countCorroboratingAdults(
  db: Firestore,
  input: { familyId: string; approverUserId: string; targetUserId: string }
): Promise<number> {
  const snapshot = await db.collection(`families/${input.familyId}/members`).get();
  let count = 0;
  snapshot.forEach((doc) => {
    if (doc.id === input.approverUserId || doc.id === input.targetUserId) return;
    if ((doc.data() as Record<string, unknown> | undefined)?.isChild === true) return;
    count += 1;
  });
  return count;
}

/**
 * FR-66(b): throw unless the approving family is old enough, or corroborated by a second
 * adult, to be trusted with a new-guardian flag clear.
 *
 * Reads one `families/{id}` doc plus the member roster, and only on the clear path — the
 * ordinary approve and the `isChild: true` grant pay nothing.
 */
export async function assertGuardianClearSeasoning(
  db: Firestore,
  input: {
    familyId: string;
    approverUserId: string;
    targetUserId: string;
    /** The pending request doc's data, for its `createdAt`. */
    requestData: Record<string, unknown> | undefined;
    /** Injectable for tests; used when the request has no readable `createdAt`. */
    nowMs?: number;
  }
): Promise<void> {
  const [familySnapshot, otherAdultMemberCount] = await Promise.all([
    db.collection("families").doc(input.familyId).get(),
    countCorroboratingAdults(db, input),
  ]);

  const requestCreatedAtMs =
    timestampToMillis(input.requestData?.createdAt) ?? input.nowMs ?? Date.now();

  const decision = evaluateGuardianClearSeasoning({
    familyCreatedAtMs: timestampToMillis(
      (familySnapshot.data() as Record<string, unknown> | undefined)?.createdAt
    ),
    requestCreatedAtMs,
    otherAdultMemberCount,
  });

  if (!decision.ok) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      GUARDIAN_CLEAR_SEASONING_MESSAGE
    );
  }
}
