import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import {
  assertRegisteredAccount,
  assertRegisteredAccountOrDeclaredChild,
} from "./callableAuth";
import { assertCallerIsNotChild, isChildAccount } from "./childAccessGuards";
import { CHILD_TARGET_NOT_SEARCHABLE_MESSAGE } from "./childAccountCore";
import { consumeInviteRateLimit } from "./inviteRateLimit";
import {
  buildPendingRequestIdentity,
  timestampToMillis,
} from "./familyJoinRequestIntegrity";
import { loadFamilyName } from "./familyInviteDisplay";

const db = admin.firestore();

export const SHARE_CODE_TYPES = ["friend", "family"] as const;

export type ShareCodeType = (typeof SHARE_CODE_TYPES)[number];

function isShareCodeType(value: unknown): value is ShareCodeType {
  return typeof value === "string" && (SHARE_CODE_TYPES as readonly string[]).includes(value);
}

/**
 * FR-67 redemption gate — the two refusals that must be INDISTINGUISHABLE.
 *
 * Two things are refused here:
 *  - a child redeeming a `friend` code. Redemption used to mint the stranger→child friend
 *    invite and leave it to be blocked at accept; the row should never exist.
 *  - a code redeemed in the wrong context — a `friend` code fed to the join-a-family screen,
 *    or a `family` code fed to the add-a-friend screen.
 *
 * They share one reply for the same reason `inviteRelationshipGate.ts` shares its own (see
 * that module's header): a share code is a bearer token an attacker can hand to anybody. If
 * "you are a child" and "wrong code type" read differently, distributing one friend code and
 * diffing the replies classifies every account that tries it — FR-24's oracle, rebuilt from
 * the other side. So both throw `permission-denied` with `CHILD_TARGET_NOT_SEARCHABLE_MESSAGE`
 * and, critically, NO `details` payload, since `details` is the same channel by another name.
 *
 * `shareCodeRedemption.test.ts` pins this against the child-target rejection field by field.
 */
export function assertShareCodeRedeemable(input: {
  callerIsChild: boolean;
  codeType: unknown;
  expectedType: ShareCodeType;
}): void {
  const typeMismatch = input.codeType !== input.expectedType;
  const childFriendCode = input.callerIsChild && input.codeType === "friend";
  if (typeMismatch || childFriendCode) {
    throw new functions.https.HttpsError(
      "permission-denied",
      CHILD_TARGET_NOT_SEARCHABLE_MESSAGE
    );
  }
}

/**
 * Generate a random 6-character alphanumeric code
 */
function generateRandomCode(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * Create a share code (friend or family type)
 * TTL: 15 minutes, multi-use
 */
export const createShareCode = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { type, familyId } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (type !== "friend" && type !== "family") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Type must be 'friend' or 'family'"
      );
    }

    if (type === "family" && !familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId required for family codes"
      );
    }

    // FR-24 (COPPA F-5b): a share code is an open invitation to strangers, so no child may
    // mint one. `redeemShareCode` deliberately keeps no such guard — redeeming is a child's
    // route back into a parent-managed family.
    await assertCallerIsNotChild(db, userId);

    // FR-66(d): a family code names the family strangers will be admitted to, so the minter
    // must actually be in it. The rules gained the same clause, but rules do not bind this
    // callable (Admin SDK), and without the check here an adult could mint a live code for
    // ANY familyId they can name — and `activeFamilyId` is readable on peer user docs.
    if (familyId) {
      const membership = await db
        .collection(`families/${familyId}/members`)
        .doc(userId)
        .get();
      if (!membership.exists) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Not a family member"
        );
      }
    }

    // Generate random code
    const code = generateRandomCode();

    // 15 minute TTL
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 15);

    const codeData: any = {
      type,
      createdBy: userId,
      code,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRevoked: false,
    };

    if (familyId) {
      codeData.familyId = familyId;
    }

    const codeRef = await db.collection("share_codes").add(codeData);

    try {
      await writeAuditLog({
        eventType: "share_code_generated",
        actorId: userId,
        subjectType: "invite",
        subjectId: codeRef.id,
        metadata: familyId ? { type, familyId } : { type },
        clientMetadata,
      });
    } catch (error) {
      functions.logger.error("share_code_generated audit log failed", error);
    }

    return {
      codeId: codeRef.id,
      code,
      expiresAt: expiresAt.toISOString(),
    };
  }
);

/**
 * Redeem a share code and create an invite.
 *
 * STAYS OPEN TO CHILDREN (FR-24/FR-26). This and `respondToFamilyInvite_UserStep` are the
 * two designated exits back into consented play, so there is no `assertCallerIsNotChild`
 * here and there must never be one — a child who cannot redeem a code cannot be admitted to
 * a family, and family admission IS consent. What FR-67 adds is narrower: a child may not
 * redeem a FRIEND code, and nobody may redeem a code of the wrong type for the screen they
 * are on.
 *
 * ORDER IS LOAD-BEARING (FR-24 + FR-67):
 *   1. resolve the code and run the child/type gate FIRST, spending no budget — otherwise a
 *      child could burn their hourly allowance on friend codes and lock themselves out of
 *      the family code that is their actual route to consent;
 *   2. then consume the rate limit, INCLUDING on the not-found path, because "not found" is
 *      the reply a brute-force search lives on and is the one that must be throttled.
 * The gate's own rejection is byte-identical to the child-target rejection — see
 * `assertShareCodeRedeemable`.
 */
export const redeemShareCode = enforcedCallable(
  async (data, context) => {
    // FR-60 (F-18): a declared child arrives here ANONYMOUS — this call is the second half
    // of the provisioning sequence that share-code entry runs (mint → bind → declare →
    // redeem), so the uid exists but has no credentials yet. The carve-out passes it on the
    // server-read `isChildAccount` flag; every other anonymous caller still fails, with a
    // byte-identical reply.
    const userId = await assertRegisteredAccountOrDeclaredChild(db, context);

    const { code, expectedType } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!code) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Code is required"
      );
    }

    // Codes are generated uppercase-only (generateRandomCode); normalize server-side
    // too so a lowercase code from any caller still matches (owner device testing,
    // 2026-08-15).
    const normalizedCode = typeof code === "string" ? code.toUpperCase() : code;

    // FR-67: which surface is redeeming. Required, because a caller who could simply omit it
    // would skip the type check entirely — which is the whole hole being closed. This is a
    // payload-shape error, uniform for every caller, and discloses nothing about anyone.
    if (!isShareCodeType(expectedType)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "expectedType must be 'friend' or 'family'"
      );
    }

    // Find code
    const codesSnapshot = await db
      .collection("share_codes")
      .where("code", "==", normalizedCode)
      .limit(1)
      .get();

    const foundDoc = codesSnapshot.empty ? null : codesSnapshot.docs[0];

    if (foundDoc) {
      assertShareCodeRedeemable({
        callerIsChild: await isChildAccount(db, userId),
        codeType: foundDoc.data().type,
        expectedType,
      });
    }

    // FR-67 throttle (OD-4: 10/hour/uid). Deliberately after the gate and before the
    // not-found throw — see the ordering note in the header.
    await consumeInviteRateLimit(db, { scope: "share_redeem", userId });

    if (!foundDoc) {
      throw new functions.https.HttpsError("not-found", "Code not found");
    }

    const codeDoc = foundDoc;
    const codeData = codeDoc.data();

    // Check if expired or revoked. An unreadable `expiresAt` counts as expired: a code whose
    // TTL cannot be established must not be honoured indefinitely.
    const expiresAtMs = timestampToMillis(codeData.expiresAt);
    if (expiresAtMs === null || expiresAtMs < Date.now() || codeData.isRevoked) {
      throw new functions.https.HttpsError("invalid-argument", "Code expired");
    }

    // Prevent self-invite
    if (codeData.createdBy === userId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Cannot use your own code"
      );
    }

    // Create invite
    const expiresAtInvite = new Date();
    expiresAtInvite.setMinutes(expiresAtInvite.getMinutes() + 15);

    // FR-86, extended to the invite itself (2026-08-26): the captain's "Waiting for
    // response" row renders the INVITEE, and FR-12 rightly denies the captain a read of a
    // non-family child's `users/{uid}` — so the identity has to travel ON the invite,
    // stamped server-side, exactly as `families/{id}/pending` rows are stamped at accept.
    // The consent-seeking flow (wave 8) awaits the child's own profile write before this
    // callable runs, so the read below sees it; a missing profile simply omits the fields
    // and the client keeps its "Pending User" fallback. Fields are pinned to
    // PENDING_REQUEST_IDENTITY_FIELDS (§312.5(c)(1) — identity for the purpose of
    // obtaining consent). The stamp always describes `toUserId`, never the sender.
    let inviteeIdentity = {};
    if (codeData.type === "family") {
      const redeemerDoc = await db.collection("users").doc(userId).get();
      inviteeIdentity = buildPendingRequestIdentity(redeemerDoc.data());
    }

    // F-44: ONE live family invite per (family, recipient).
    //
    // Device pass 2026-08-16: the owner entered the same family code twice from one child
    // account. Each entry minted its own invite, each invite was accepted, and the captain
    // got two identical "Pending User" rows for a single child — the state that then let a
    // decline on one row delete the account the other row was waiting on. `sendFamilyInvite`
    // has rejected duplicate pending invites since F-8; redemption never did, and redemption
    // is the child's path, so it is the one that mattered.
    //
    // Reuse rather than reject: a second entry of a live code is an ordinary "did that
    // work?" retry, and FR-24 forbids growing the set of things a child-reachable surface can
    // refuse. The caller gets the invite id they already had, refreshed onto the code they
    // just entered, and `respondToFamilyInvite_UserStep` sees one invite where it used to see
    // two. Accepted invites are handled there, not here: retiring them is part of resolving
    // the pending row they produced.
    if (codeData.type === "family" && typeof codeData.familyId === "string") {
      const liveInvites = await db
        .collection("invites")
        .where("familyId", "==", codeData.familyId)
        .where("toUserId", "==", userId)
        .where("type", "==", "family")
        .where("status", "==", "pending")
        .limit(1)
        .get();

      if (!liveInvites.empty) {
        const reusedInvite = liveInvites.docs[0];
        const refresh: Record<string, unknown> = {
          fromUserId: codeData.createdBy,
          method: "code",
          codeId: codeDoc.id,
          expiresAt: admin.firestore.Timestamp.fromDate(expiresAtInvite),
          // Re-stamp the invitee's CURRENT identity (FR-86 comment above): a retry after a
          // rename must not leave the captain reading a stale name off the reused invite.
          ...inviteeIdentity,
        };
        const familyName = await loadFamilyName(codeData.familyId);
        if (familyName) {
          refresh.familyName = familyName;
        }
        await reusedInvite.ref.update(refresh);

        await writeAuditLog({
          eventType: "share_code_used",
          actorId: userId,
          subjectType: "invite",
          subjectId: reusedInvite.id,
          metadata: {
            codeId: codeDoc.id,
            type: codeData.type,
            reusedExistingInvite: true,
          },
          clientMetadata,
        });

        return {
          inviteId: reusedInvite.id,
          type: codeData.type,
          familyId: codeData.familyId,
        };
      }
    }

    const inviteData: any = {
      type: codeData.type,
      fromUserId: codeData.createdBy,
      toUserId: userId,
      status: "pending",
      method: "code",
      codeId: codeDoc.id,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAtInvite),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (codeData.familyId) {
      inviteData.familyId = codeData.familyId;
      if (codeData.type === "family") {
        const familyName = await loadFamilyName(codeData.familyId);
        if (familyName) {
          inviteData.familyName = familyName;
        }
        // FR-86 invitee identity — see the comment above `inviteeIdentity`.
        Object.assign(inviteData, inviteeIdentity);
      }
    }

    const inviteRef = await db.collection("invites").add(inviteData);

    await writeAuditLog({
      eventType: "share_code_used",
      actorId: userId,
      subjectType: "invite",
      subjectId: inviteRef.id,
      metadata: { codeId: codeDoc.id, type: codeData.type },
      clientMetadata,
    });

    return {
      inviteId: inviteRef.id,
      type: codeData.type,
      familyId: codeData.familyId,
    };
  }
);

