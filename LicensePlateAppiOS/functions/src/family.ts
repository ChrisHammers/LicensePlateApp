import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { canAddMemberToFamily, assertUserIsRegistered, recipientNotRegisteredMessage, isUserSearchable } from "./utils/validation";
import { writeAuditLog } from "./audit";
import { auditValueHash } from "./auditRedaction";
import { getFCMTokenForSocialPush, sendPushNotification } from "./utils/notifications";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";
import {
  assertRegisteredAccount,
  assertRegisteredAccountOrDeclaredChild,
} from "./callableAuth";
import { loadFamilyName } from "./familyInviteDisplay";
import {
  PENDING_FAMILY_INVITE_EXISTS_MESSAGE,
  shouldRejectDuplicatePendingFamilyInvite,
} from "./familyInviteDuplicate";
import {
  familyMembershipGrantUserUpdate,
  familyMembershipLeaveUserUpdate,
} from "./wasEverInFamilyUserUpdates";
import { canRemoveFamilyMember } from "./familyMemberRemovalPolicy";
import {
  CHILD_TARGET_NOT_SEARCHABLE_MESSAGE,
  evaluateApprovalChildDeclaration,
  isChildWithActiveFamilyUserData,
  isUnconsentedChildUserData,
} from "./childAccountCore";
import {
  CROSS_FAMILY_JOIN_REQUEST_LIMIT,
  JOIN_REQUEST_PENDING_STATUS,
  JOIN_REQUEST_SUPERSEDED_STATUS,
  PENDING_FAMILY_REQUEST_FIELD,
  assertGuardianClearSeasoning,
  assertJoinRequestLineage,
  buildJoinRequestLineage,
  buildPendingFamilyRequestStamp,
  buildPendingRequestIdentity,
  findLivePendingJoinRequests,
  findLivePendingJoinRequestsInOtherFamilies,
  pendingRowFamilyId,
} from "./familyJoinRequestIntegrity";
import { stageJoinRequestRetirement } from "./pendingJoinRequestExpiry";
import {
  writeChildConsentCorrected,
  writeChildConsentGranted,
  writeChildMembershipRevocation,
} from "./childConsent";
import { applyChildProtectionsAfterFlagSet } from "./familyChildStatusFlows";
import { assertCallerIsNotChild } from "./childAccessGuards";
import { currentRevenueCatApiKey } from "./accountDeletion";
import {
  CHILD_DECLARED_AT_FIELD,
  deleteProvisionalChildAccountIfNeverConsented,
} from "./provisionalChildAccounts";
import { createConsentRequestForApproval } from "./consentRequests";
import {
  CONSENT_REQUESTS_COLLECTION,
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
} from "./consentRequestsCore";

const db = admin.firestore();

/**
 * FR-59.1: the guardian's own online contact information, for the consent-request email
 * (§312.5(c)(1)). Auth email first (the registered account's credential), then the
 * owner-written `private/contact` doc — the same resolution order the welcome email uses.
 */
async function resolveGuardianEmail(guardianUid: string): Promise<string | null> {
  try {
    const authUser = await admin.auth().getUser(guardianUid);
    if (authUser.email && authUser.email.length > 0) return authUser.email;
  } catch {
    // Fall through to the contact doc — an Auth lookup failure must not block consent.
  }
  const contact = await db
    .collection("users")
    .doc(guardianUid)
    .collection("private")
    .doc("contact")
    .get();
  const email = contact.data()?.email;
  return typeof email === "string" && email.length > 0 ? email : null;
}

/**
 * Every family invite into `familyId` for `toUserId` that has not reached a terminal state.
 *
 * Two indexed queries rather than one unindexed three-equality scan: the composite index
 * `(familyId, toUserId, type, status)` already exists for the status-filtered form, and the
 * two statuses are exactly the two live ones — `pending` (minted, unanswered) and `accepted`
 * (answered, awaiting the captain). `expired` and `declined` are terminal and never revive.
 */
async function liveFamilyInvitesFor(
  familyId: string,
  toUserId: string
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const [pending, accepted] = await Promise.all(
    ["pending", "accepted"].map((status) =>
      db
        .collection("invites")
        .where("familyId", "==", familyId)
        .where("toUserId", "==", toUserId)
        .where("type", "==", "family")
        .where("status", "==", status)
        .limit(10)
        .get()
    )
  );
  return [...pending.docs, ...accepted.docs];
}

/**
 * Create a new family
 */
export const createFamily = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { name } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!name || typeof name !== "string" || name.trim().length === 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Family name is required"
      );
    }

    // FR-24 (COPPA F-5b): a child cannot found a family — that would make them their own
    // consenting manager (§4: parent/manager = creator|captain) and hand them the
    // authority to admit strangers.
    await assertCallerIsNotChild(db, userId);

    // Check if user already has an active family (unless retired general)
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data()!;
    
    if (!userData.isRetiredGeneral && userData.activeFamilyId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "User already has an active family"
      );
    }

    // Create family
    const familyData = {
      name: name.trim(),
      creatorId: userId,
      status: "active",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const familyRef = await db.collection("families").add(familyData);

    // Add creator as member with creator role
    await familyRef.collection("members").doc(userId).set({
      role: "creator",
      permissions: {
        canInvite: true,
        canEditSettings: true,
      },
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection("users").doc(userId).update(
      familyMembershipGrantUserUpdate({
        familyId: familyRef.id,
        isRetiredGeneral: !!userData.isRetiredGeneral,
      })
    );

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_CREATED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyRef.id,
      metadata: { name: name.trim() },
      clientMetadata,
    });

    return { familyId: familyRef.id };
  }
);

/**
 * Send a family invite
 */
export const sendFamilyInvite = enforcedCallable(
  async (data, context) => {
    const fromUserId = assertRegisteredAccount(context);

    const { toUserId, familyId, method } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!toUserId || !familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "toUserId and familyId are required"
      );
    }

    try {
      await assertUserIsRegistered(toUserId);
    } catch (error) {
      if (error instanceof Error && error.message === "User not found") {
        throw new functions.https.HttpsError("not-found", "User not found");
      }
      throw new functions.https.HttpsError(
        "failed-precondition",
        recipientNotRegisteredMessage
      );
    }

    // FR-24 (COPPA F-5b): a child never sends family invites. Managers are creators or
    // captains and no MVP path makes a child either, but the guard is the server-side
    // backstop behind the client hiding the control.
    await assertCallerIsNotChild(db, fromUserId);

    // Verify sender is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(fromUserId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can invite"
      );
    }

    // Get target user to determine role
    const targetUserDoc = await db.collection("users").doc(toUserId).get();
    if (!targetUserDoc.exists) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const targetUserData = targetUserDoc.data()!;

    // FR-15 (COPPA F-5b): a child who already belongs to a parent-managed family may not be
    // invited into another one — that would swap their consenting manager without any
    // consent capture. Checked on EVERY method (including `search`, which skips the
    // email/phone privacy gate below) and worded exactly like the privacy opt-out so the
    // sender cannot infer the target is a child. Inviting an UNCONSENTED child (flag true,
    // no active family) stays allowed: that is the path back to consented play.
    if (isChildWithActiveFamilyUserData(targetUserData)) {
      await writeAuditLog({
        eventType: "invite_auto_rejected_not_searchable",
        actorId: fromUserId,
        subjectType: "user",
        subjectId: toUserId,
        metadata: { familyId, method: method || "search" },
        clientMetadata,
      });
      throw new functions.https.HttpsError(
        "permission-denied",
        CHILD_TARGET_NOT_SEARCHABLE_MESSAGE
      );
    }

    const newRole = targetUserData.isRetiredGeneral
      ? "retired_general"
      : "scout"; // Default to scout for new members

    // Check if user can be added
    const canAdd = await canAddMemberToFamily(familyId, newRole, toUserId);
    if (!canAdd.canAdd) {
      await writeAuditLog({
        eventType: "invite_auto_rejected_user_already_in_family",
        actorId: fromUserId,
        subjectType: "user",
        subjectId: toUserId,
        metadata: { familyId, reason: canAdd.reason },
        clientMetadata,
      });
      throw new functions.https.HttpsError(
        "failed-precondition",
        canAdd.reason || "Cannot add user to family"
      );
    }

    // Check privacy if searching by email/phone
    if (method === "email" || method === "phone") {
      const searchable = await isUserSearchable(
        toUserId,
        method === "email" ? "email" : "phone"
      );
      if (!searchable) {
        await writeAuditLog({
          eventType: "invite_auto_rejected_not_searchable",
          actorId: fromUserId,
          subjectType: "user",
          subjectId: toUserId,
          metadata: { familyId, method },
          clientMetadata,
        });
        throw new functions.https.HttpsError(
          "permission-denied",
          "User is not searchable by this method"
        );
      }
    }

    // Reject duplicate pending invites for the same family + invitee (any captain/creator)
    const existingInvite = await db
      .collection("invites")
      .where("familyId", "==", familyId)
      .where("toUserId", "==", toUserId)
      .where("type", "==", "family")
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (shouldRejectDuplicatePendingFamilyInvite(existingInvite.empty)) {
      throw new functions.https.HttpsError(
        "already-exists",
        PENDING_FAMILY_INVITE_EXISTS_MESSAGE
      );
    }

    // Create invite
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + 15);

    const familyName = await loadFamilyName(familyId);

    const inviteData: Record<string, unknown> = {
      type: "family",
      fromUserId,
      toUserId,
      familyId,
      status: "pending",
      method: method || "search",
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      // FR-86, extended to invites (2026-08-26): stamp the INVITEE's identity so the
      // captain's "Waiting for response" row can render a child the captain is forbidden
      // (FR-12) from resolving via users/{uid}. Same pinned two-field pair as the pending
      // row (§312.5(c)(1)); `targetUserData` was already read above for the FR-15 gate,
      // so this adds no read. Absent fields are omitted — the client keeps its
      // "Pending User" fallback.
      ...buildPendingRequestIdentity(targetUserData),
    };

    if (familyName) {
      inviteData.familyName = familyName;
    }

    const inviteRef = await db.collection("invites").add(inviteData);

    // Send push notification (gated by recipient notificationPrefs.family)
    const fcmToken = await getFCMTokenForSocialPush(toUserId, "family");
    if (fcmToken) {
      await sendPushNotification(
        fcmToken,
        "Family Invitation",
        familyName
          ? `You've been invited to join ${familyName}`
          : "You've been invited to join a family",
        {
          type: "family_invite",
          inviteId: inviteRef.id,
          familyId,
          deepLink: `roadtrip-royale://invite/family?inviteId=${inviteRef.id}&familyId=${familyId}`,
        }
      );
    }

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_INVITE_SENT",
      actorId: fromUserId,
      subjectType: "invite",
      subjectId: inviteRef.id,
      metadata: { toUserId, familyId, method },
      clientMetadata,
    });

    return { inviteId: inviteRef.id };
  }
);

/**
 * User accepts family invite (step 1) - creates pending request
 */
export const respondToFamilyInvite_UserStep = enforcedCallable(
  async (data, context) => {
    // FR-60 (F-18): the second of the two consent exits. A child provisioned at share-code
    // entry is still ANONYMOUS here — the carve-out lets a server-verified declared child
    // through and leaves every other anonymous caller with the byte-identical refusal.
    const userId = await assertRegisteredAccountOrDeclaredChild(db, context);

    const { inviteId, response } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!inviteId || !response) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "inviteId and response are required"
      );
    }

    if (response !== "accept" && response !== "decline") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Response must be 'accept' or 'decline'"
      );
    }

    // Get invite
    const inviteDoc = await db.collection("invites").doc(inviteId).get();

    if (!inviteDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Invite not found");
    }

    const inviteData = inviteDoc.data()!;

    // Verify user is the recipient
    if (inviteData.toUserId !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not authorized to respond to this invite"
      );
    }

    // F-44: re-accepting an invite THIS user already accepted is the same request arriving
    // twice, not a new one. Now that `redeemShareCode` reuses a live invite instead of
    // minting a rival, a second code entry lands back on an invite already marked accepted —
    // and the child would have hit "Invite already responded to" on the retry that used to
    // silently work (by creating the duplicate row this whole change exists to prevent).
    //
    // Widened here rather than in the gate above because it must stay narrow: same recipient
    // (checked already), same direction (accept only), and an already-accepted invite only.
    // A declined or expired invite is still terminal, and the accept path below reuses the
    // pending row, so a retry cannot multiply anything. FR-24 is satisfied in the safe
    // direction — no new refusal reaches a child-reachable surface, one fewer does.
    const repeatAccept = response === "accept" && inviteData.status === "accepted";
    if (inviteData.status !== "pending" && !repeatAccept) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Invite already responded to"
      );
    }

    const batch = db.batch();

    // Update invite status
    batch.update(inviteDoc.ref, {
      status: response === "accept" ? "accepted" : "declined",
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    let pendingRequestId: string | null = null;
    const familyId =
      typeof inviteData.familyId === "string" ? inviteData.familyId : null;

    if (response === "accept") {
      if (!familyId) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Invite is missing familyId"
        );
      }

      // Create pending join request (awaiting captain approval).
      //
      // FR-66(a): stamp the invite that authorised this request — and the share code behind
      // it, when `redeemShareCode` minted the invite. `invites` has been server-created-only
      // since FR-16(a) and `pending` now is too, so the stamp chains a join request back to
      // a document no client could have forged. `approveFamilyJoinRequest_CaptainStep`
      // refuses to approve a row without one.
      //
      // FR-86 (F-43): and stamp who is asking. The captain cannot read a non-member child's
      // user doc (FR-12), so without this they approve a raw uid — and FR-31's "I confirm I
      // am THIS CHILD's parent or legal guardian" cannot be truthfully affirmed about one.
      // Username and avatar only; see `PENDING_REQUEST_IDENTITY_FIELDS`.
      //
      // ONE read of the requester's own doc, used twice: the FR-86 identity stamp on the row,
      // and the FR-88 pending-state stamp written back onto that same doc below.
      const requesterDoc = await db.collection("users").doc(userId).get();
      const requesterData = requesterDoc.data() as
        | Record<string, unknown>
        | undefined;

      const requestData = {
        userId,
        requestedBy: inviteData.fromUserId,
        method: inviteData.method,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        ...buildJoinRequestLineage({
          inviteId: inviteDoc.id,
          codeId: inviteData.codeId,
        }),
        ...buildPendingRequestIdentity(requesterData),
      };

      // F-44: ONE live row per (family, user). Accepting a second invite REFRESHES the
      // request already waiting on a decision rather than queueing a rival beside it.
      //
      // Two rows for one child is what wedged the owner's captain queue on 2026-08-16: they
      // are indistinguishable in the UI, and resolving either one ran FR-60(c) cleanup and
      // deleted the account the other was pointing at. A full `set` (not `update`) so the
      // refreshed row carries the new invite's lineage exactly — a stale `originCodeId` from
      // the superseded invite would misattribute the request's provenance.
      //
      // `createdAt` moves forward with it. That is the safe direction for FR-66(b): a newer
      // request is younger relative to the family, so the seasoning window gets HARDER to
      // clear, never easier.
      const [existingRow, ...supersededRows] = await findLivePendingJoinRequests(db, {
        familyId,
        userId,
      });

      // FR-59.1: a row already awaiting guardian confirmation is PAST the child's part —
      // the captain approved, the guardian's email is out. A re-accept (child re-entered
      // the code, "did it work?") must not reset it to `pending`: that would silently
      // demote a decision in flight and orphan the live consent request. Idempotent
      // success, exactly like the repeat-accept above.
      if (existingRow?.data().status === JOIN_REQUEST_AWAITING_GUARDIAN_STATUS) {
        await batch.commit();
        return { success: true, requestId: existingRow.id };
      }

      if (existingRow) {
        pendingRequestId = existingRow.id;
        batch.set(existingRow.ref, requestData);
        for (const stale of supersededRows) {
          batch.update(stale.ref, {
            status: JOIN_REQUEST_SUPERSEDED_STATUS,
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } else {
        const requestRef = db.collection(`families/${familyId}/pending`).doc();
        pendingRequestId = requestRef.id;
        batch.set(requestRef, requestData);
      }

      // FR-88: the row's shadow on the one document the requester can always read. SAME
      // batch as the row itself, so "a pending row exists" and "my user doc says a family is
      // deciding" cannot disagree — the disagreement IS the bug (a decline that left the
      // device's guess standing forever).
      //
      // Nothing extra is needed for the superseded rows retired just above: they belong to
      // this same user, and this one stamp now names the row that survived them.
      //
      // `batch.update` (not set-merge) and guarded on existence, because a set-merge on a
      // missing doc would MINT a `users/{uid}` holding nothing but this field. Unconsented
      // children only — see `PENDING_FAMILY_REQUEST_FIELD` for why an adult must not carry it.
      if (requesterDoc.exists && isUnconsentedChildUserData(requesterData)) {
        batch.update(db.collection("users").doc(userId), {
          [PENDING_FAMILY_REQUEST_FIELD]: buildPendingFamilyRequestStamp({
            familyId,
            requestId: pendingRequestId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }),
        });
      }

      // Retire every OTHER live invite into this family for this user — the one this row used
      // to be stamped with, and any the child minted by re-entering the code. Left alive they
      // read as separate live invitations on the requester's dashboard and, worse, an
      // unaccepted one lapsing on its 15-minute TTL used to run `expireInvitesAndCodes`'
      // FR-60(c) cleanup and delete an account that had a pending row waiting.
      for (const stale of await liveFamilyInvitesFor(familyId, userId)) {
        if (stale.id === inviteDoc.id) continue;
        batch.update(stale.ref, {
          status: "expired",
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await writeAuditLog({
        eventType: "family_join_request_created",
        actorId: userId,
        subjectType: "invite",
        subjectId: inviteId,
        metadata: { familyId },
        clientMetadata,
      });
    }

    await batch.commit();

    // FR-60(c), extended 2026-08-27 (owner ruling): a CHILD's own decline deletes their
    // never-consented provisional account inline, exactly as the captain's decline does —
    // "7 days of being able to see the child" (the FR-77 backstop's window) is footprint
    // with no decision left to serve. The helper's guards make this safe to call from a
    // second site: no-op for adults, consented children, sticky post-revocation children
    // (FR-28/OD-3), and anyone with a live pending row in ANY family — so declining one
    // invite while an accepted request awaits another captain deletes nothing. Runs AFTER
    // `batch.commit()` (the helper's documented contract: the predicate must see the
    // decision already applied), and non-fatally: the decline itself has committed, and a
    // failure here leaves the account for the same 7-day backstop that always existed.
    //
    // The caller IS the account being deleted. That is the designed FR-60(c) shape — the
    // device keeps its age answer and ratchet, the vanished-session machinery returns it
    // to a local-first child, and a later share code re-provisions cleanly (see
    // `provisionalChildAccounts.ts` header). The captain-decline path has produced this
    // exact client state since wave 6; nothing new lands on the device side.
    if (response === "decline") {
      try {
        await deleteProvisionalChildAccountIfNeverConsented(db, {
          userId,
          actorId: userId,
          clientMetadata,
          revenueCatApiKey: currentRevenueCatApiKey(),
        });
      } catch (error) {
        functions.logger.error(
          "FR-60(c): provisional child cleanup after self-decline failed; backstop sweep will retry",
          { childUserId: userId, error }
        );
      }
    }

    // Notify creators/captains that a join request needs approval (Family pref gated).
    if (response === "accept" && familyId && pendingRequestId) {
      await notifyFamilyManagersOfJoinRequest({
        familyId,
        requestId: pendingRequestId,
        requesterUserId: userId,
      });
    }

    return { success: true };
  }
);

/**
 * FCM creators/captains when someone accepts an invite and needs approval.
 */
async function notifyFamilyManagersOfJoinRequest(args: {
  familyId: string;
  requestId: string;
  requesterUserId: string;
}): Promise<void> {
  const { familyId, requestId, requesterUserId } = args;
  const membersSnap = await db.collection(`families/${familyId}/members`).get();
  const managerIds: string[] = [];
  membersSnap.forEach((doc) => {
    const role = doc.data().role;
    if (role === "creator" || role === "captain") {
      managerIds.push(doc.id);
    }
  });

  const deepLink = `roadtrip-royale://family/${familyId}/pending`;
  await Promise.all(
    managerIds.map(async (managerId) => {
      if (managerId === requesterUserId) {
        return;
      }
      const fcmToken = await getFCMTokenForSocialPush(managerId, "family");
      if (!fcmToken) {
        return;
      }
      try {
        await sendPushNotification(
          fcmToken,
          "Family Join Request",
          "Someone wants to join your family",
          {
            type: "family_join_request",
            familyId,
            requestId,
            deepLink,
          }
        );
      } catch (error) {
        console.error(
          `Error sending family_join_request push to ${managerId}:`,
          error
        );
      }
    })
  );
}

/**
 * Captain approves family join request (step 2) - adds member
 */
export const approveFamilyJoinRequest_CaptainStep = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, requestId, response } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !requestId || !response) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId, requestId, and response are required"
      );
    }

    if (response !== "approve" && response !== "decline") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Response must be 'approve' or 'decline'"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can approve requests"
      );
    }

    // Get request
    const requestDoc = await db
      .collection(`families/${familyId}/pending`)
      .doc(requestId)
      .get();

    if (!requestDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Request not found");
    }

    const requestData = requestDoc.data()!;
    const currentStatus = requestData.status;

    if (
      currentStatus !== "pending" &&
      currentStatus !== JOIN_REQUEST_AWAITING_GUARDIAN_STATUS
    ) {
      // F-44: re-invoking the SAME decision is a no-op success, not an error. The captain's
      // tap can land twice — a retry after a client-side timeout, or two taps on rows this
      // very function retired together — and a `failed-precondition` there reads to the
      // captain as "the queue is broken" for work that is in fact already done.
      //
      // `expired` counts as declined-equivalent ONLY for a decline: it is what a duplicate
      // row wears after a sibling row carried the decision, so declining it is asking for a
      // state it is already in. Approving one is still refused — the decision that mattered
      // was recorded on the sibling, and this row has no lineage claim to re-open it.
      const alreadyDeclined =
        currentStatus === "declined" || currentStatus === "expired";
      if (
        (response === "approve" && currentStatus === "approved") ||
        (response === "decline" && alreadyDeclined)
      ) {
        return { success: true };
      }
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Request already resolved"
      );
    }
    // FR-59.1: `awaiting_guardian` rows stay actionable BOTH ways. Approve re-enters the
    // grant path, whose consent-request creation is idempotent (old clients render the
    // row as pending and captains WILL re-tap — every tap after the first reuses the
    // live request, no fresh email). Decline cancels the outstanding request below.

    // F-44: any OTHER live row for the same user in this family is resolved by THIS
    // operation, in the same batch. Duplicates are indistinguishable to the captain, so
    // leaving one behind leaves a row whose account has just been admitted (nothing to
    // approve) or deleted (nothing to approve, ever) — the wedge the owner hit on
    // 2026-08-16. Read before the batch, resolved inside it.
    const duplicateRequests = await findLivePendingJoinRequests(db, {
      familyId,
      userId: requestData.userId,
      excludeRequestId: requestId,
    });

    const batch = db.batch();

    // COPPA FR-25: child follow-ons that must run only after the membership batch
    // commits (index purge, invite/friend cleanup, consent record).
    let childFollowUp:
      | { kind: "grant"; expectedAgeOutYear?: number; targetUserData: Record<string, unknown> }
      | { kind: "clear_new_guardian"; correctionReason: string }
      | null = null;

    if (response === "approve") {
      // FR-66(a): only a request an invite produced may be approved. Decline stays open
      // below, so a manager can always clear a malformed row out of their queue.
      assertJoinRequestLineage(requestData);

      // Get target user to determine role
      const targetUserDoc = await db
        .collection("users")
        .doc(requestData.userId)
        .get();

      if (!targetUserDoc.exists) {
        throw new functions.https.HttpsError("not-found", "User not found");
      }

      const targetUserData = targetUserDoc.data()!;
      const newRole = targetUserData.isRetiredGeneral
        ? "retired_general"
        : "scout";

      // COPPA FR-1 / FR-25: the approval payload may (and, for sticky targets, MUST)
      // declare the member's child status. `isChild: true` is a consent capture and
      // requires both acknowledgments (FR-31); `isChild: false` on a flagged target is
      // the new-guardian correction. Absent `isChild` on a flagged target is rejected —
      // a child flag is never silently laundered through re-admission.
      const childDecision = evaluateApprovalChildDeclaration({
        payloadIsChild: data?.isChild,
        consentAcknowledged: data?.consentAcknowledged,
        guardianAffirmed: data?.guardianAffirmed,
        correctionReason: data?.correctionReason,
        expectedAgeOutYear: data?.expectedAgeOutYear,
        targetIsChildAccount: targetUserData.isChildAccount === true,
        nowYear: new Date().getUTCFullYear(),
      });
      if (childDecision.kind === "reject") {
        throw new functions.https.HttpsError(childDecision.code, childDecision.message);
      }
      if (childDecision.kind === "grant") {
        childFollowUp = {
          kind: "grant",
          expectedAgeOutYear: childDecision.expectedAgeOutYear,
          targetUserData,
        };
      } else if (childDecision.kind === "clear_new_guardian") {
        // FR-66(b): evidence is necessary but not sufficient — a fabricated guardian can
        // supply a reason and tick both boxes. The family itself must also look real.
        await assertGuardianClearSeasoning(db, {
          familyId,
          approverUserId: userId,
          targetUserId: requestData.userId,
          requestData,
        });
        childFollowUp = {
          kind: "clear_new_guardian",
          correctionReason: childDecision.correctionReason,
        };
      }

      // Check if user can still be added (limits may have changed)
      const canAdd = await canAddMemberToFamily(
        familyId,
        newRole,
        requestData.userId
      );
      if (!canAdd.canAdd) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          canAdd.reason || "Cannot add user to family"
        );
      }

      // FR-59/FR-59.1 email_plus (owner go 2026-08-27): for a CHILD grant, the captain's
      // approve is no longer the admission — it is the FR-31 affirmation plus the request
      // for verifiable consent. Everything above validated exactly as before (lineage,
      // acks, seasoning, capacity); admission itself moves to the guardian's emailed
      // confirmation (`confirmParentalConsent`), where the FR-64 transaction commits
      // consent record + guardianship + membership together. Cross-family retirement and
      // the child's push move with it — approve must leave other captains' rows
      // answerable, because an expired link means nothing was ever granted.
      //
      // Adults and `clear_new_guardian` corrections keep the immediate path below.
      if (childDecision.kind === "grant") {
        const guardianEmail = await resolveGuardianEmail(userId);
        if (!guardianEmail) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Add an email address to your account to confirm consent"
          );
        }

        const consentRequest = await createConsentRequestForApproval(db, {
          familyId,
          childUserId: requestData.userId,
          joinRequestId: requestId,
          guardianUid: userId,
          guardianRole: memberRole,
          guardianEmail,
          newRole,
          childUserName:
            typeof targetUserData.userName === "string" ? targetUserData.userName : "",
          expectedAgeOutYear: childFollowUp?.kind === "grant"
            ? childFollowUp.expectedAgeOutYear
            : undefined,
        });

        const awaitingBatch = db.batch();
        if (currentStatus === "pending") {
          // Answered, not resolved: no `resolvedAt`, and the FR-88 stamp stays — a
          // family IS still deciding. Every liveness predicate reads this status as
          // live (`LIVE_JOIN_REQUEST_STATUSES`), which is what keeps the FR-77 sweep
          // off the child mid-consent.
          awaitingBatch.update(requestDoc.ref, {
            status: JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
          });
        }
        for (const duplicate of duplicateRequests) {
          awaitingBatch.update(duplicate.ref, {
            status: JOIN_REQUEST_SUPERSEDED_STATUS,
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await awaitingBatch.commit();

        await writeAuditLog({
          eventType: "family_join_guardian_confirmation_requested",
          actorId: userId,
          subjectType: "family",
          subjectId: familyId,
          metadata: {
            requestId,
            userId: requestData.userId,
            consentRequestId: consentRequest.requestId,
            reusedExisting: consentRequest.reusedExisting,
          },
          clientMetadata,
        });

        return { success: true, awaitingGuardianConfirmation: true };
      }

      // Add member
      const memberData: Record<string, unknown> = {
        role: newRole,
        permissions: {
          canInvite: false,
          canEditSettings: false,
        },
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      // FR-59.1: the `grant` kind exited above into the consent-request path — this
      // immediate-admission section serves adults and `clear_new_guardian` corrections
      // only, so `isChild: true` can never be written here again.
      if (childDecision.kind === "clear_new_guardian") {
        memberData.isChild = false;
      }

      batch.set(
        db.collection(`families/${familyId}/members`).doc(requestData.userId),
        memberData
      );

      // Sticky family unlock + activeFamilyId (skip activeFamilyId for retired general).
      // FR-4/FR-25: the child flag and the FR-35(b) linkedPlatforms strip ride the same
      // batched user update as the membership grant.
      const grantUpdate = familyMembershipGrantUserUpdate({
        familyId,
        isRetiredGeneral: !!targetUserData.isRetiredGeneral,
        isChild: childDecision.kind === "clear_new_guardian" ? false : undefined,
      });
      // FR-60(c): admission CLOSES the redemption window, so the marker that opened it goes
      // with the same batch. Belt-and-braces with `wasEverInFamily` (also set here): the
      // transient-account sweep can only see accounts that still carry this stamp, so an
      // admitted child — and, later, a sticky post-revocation child — is invisible to it by
      // construction rather than by the sweep's own predicate. A no-op for adults.
      grantUpdate[CHILD_DECLARED_AT_FIELD] = admin.firestore.FieldValue.delete();
      // FR-88: the decision has arrived, so nobody is deciding any more. Same batch as the
      // status flip, and unconditional for the same reason the line above is — an adult
      // never carries the field, and deleting an absent key is a no-op.
      grantUpdate[PENDING_FAMILY_REQUEST_FIELD] = admin.firestore.FieldValue.delete();
      batch.update(
        db.collection("users").doc(requestData.userId),
        grantUpdate
      );

      // Update request status
      batch.update(requestDoc.ref, {
        status: "approved",
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // F-44: the duplicates go with it — retired, NOT declined, because the child was
      // admitted and "declined" on a sibling row would tell them the opposite. Critically,
      // this is a row-status write and nothing else: approval must NEVER reach
      // `deleteProvisionalChildAccountIfNeverConsented`, and the only call to it in this
      // callable is in the decline branch's follow-up below, guarded on `response`.
      for (const duplicate of duplicateRequests) {
        batch.update(duplicate.ref, {
          status: JOIN_REQUEST_SUPERSEDED_STATUS,
          resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Retire the matching accepted invite, mirroring the decline branch: left in
      // "accepted" forever, it reads as a live "awaiting approval" request on the
      // requester's dashboard after they later leave or are removed (F-8 bug B).
      const approvedMatchingInvites = await db
        .collection("invites")
        .where("familyId", "==", familyId)
        .where("toUserId", "==", requestData.userId)
        .where("type", "==", "family")
        .where("status", "==", "accepted")
        .limit(5)
        .get();

      for (const inviteDoc of approvedMatchingInvites.docs) {
        // "expired" (not a new status): the client parses unknown statuses as
        // .pending, which would resurrect the invite as live. Expired is terminal
        // client-side and the retention job cleans it up.
        batch.update(inviteDoc.ref, {
          status: "expired",
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // OWNER DECISION 2026-08-17: "on accept of a family, we should delete all other
      // pending... the backend should be authoritative."
      //
      // A uid holds exactly one `activeFamilyId`, and the grant above just set it. From this
      // commit onward every live `pending` row this person holds in ANOTHER family is
      // unapprovable — `canAddMemberToFamily` answers "User is already in another active
      // family", and FR-15 refuses even to invite a child who has one — but it still renders
      // as an ordinary request. That family's captain reads a name, affirms guardianship over
      // it (FR-31), taps approve, and gets a failure for a decision that could never have
      // succeeded. F-44 already retires SIBLING rows inside this family for exactly that
      // reason; the boundary was never the family, it was the user.
      //
      // Deliberately not left to the device: the client is offline-first and cannot see the
      // other family's subcollection at all (`firestore.rules` limits `pending` reads to
      // members), so the server is the only place this can be true.
      //
      // THE ONE EXCEPTION IS THE RETIRED GENERAL, and it is not a special case bolted on — it
      // is the same rule. `familyMembershipGrantUserUpdate` does not write `activeFamilyId`
      // for them and `canAddMemberToFamily` exempts them from the one-family check, precisely
      // so a grandparent can belong to several families at once. Their other rows are still
      // APPROVABLE, so retiring them would destroy live, legitimate requests in two other
      // captains' queues. The retirement is keyed off the very variable that decides whether
      // this grant is exclusive, so the two can never disagree.
      let crossFamilyRetirement = { rows: 0, stamps: 0, invites: 0 };
      if (newRole !== "retired_general") {
        const strandedElsewhere = await findLivePendingJoinRequestsInOtherFamilies(db, {
          userId: requestData.userId,
          excludeFamilyId: familyId,
        });
        if (strandedElsewhere.truncated) {
          // No silent caps. The unanswered-row sweep retires the remainder on its own clock.
          functions.logger.warn(
            "cross-family join-request retirement hit its per-approval bound; the rest will be retired by the unanswered-row sweep",
            {
              familyId,
              newMemberId: requestData.userId,
              limit: CROSS_FAMILY_JOIN_REQUEST_LIMIT,
            }
          );
        }
        // Row + FR-88 stamp + origin invite, through the same helper the unanswered-row sweep
        // uses, so "retired" cannot come to mean two different things. `expired`, never
        // `declined`: nobody refused, and the client's `InviteStatus` fails OPEN on an unknown
        // raw value (parsing it back as `.pending`), so only its four strings are safe.
        //
        // Batch discipline: a commit carrying two writes for one document is REJECTED, and
        // this batch already holds the new member's user doc and this family's accepted
        // invites. Both are declared here rather than rediscovered.
        //
        // FR-88 in particular: `grantUpdate` above already deletes the child's ONE stamp, and
        // after this retirement that clear is exactly true — no live row survives anywhere. A
        // second clear would add nothing and invalidate the commit.
        crossFamilyRetirement = await stageJoinRequestRetirement(
          db,
          batch,
          strandedElsewhere.rows,
          {
            skipDocumentPaths: new Set<string>([
              db.collection("users").doc(requestData.userId).path,
              ...approvedMatchingInvites.docs.map((inviteDoc) => inviteDoc.ref.path),
            ]),
          }
        );
      }

      await writeAuditLog({
        eventType: "AUDIT_FAMILY_JOIN_APPROVED",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: {
          newMemberId: requestData.userId,
          role: newRole,
          crossFamilyRetiredRequestCount: crossFamilyRetirement.rows,
          crossFamilyRetiredInviteCount: crossFamilyRetirement.invites,
        },
        clientMetadata,
      });
    } else {
      // Decline request — also flip the matching accepted invite so the requester's empty dashboard clears
      batch.update(requestDoc.ref, {
        status: "declined",
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // FR-59.1: declining an awaiting-guardian row also cancels the outstanding consent
      // request, so a lapsed captain decision cannot be resurrected by a stale email link
      // — the confirmation endpoint re-reads the request's status inside its transaction
      // and a superseded request refuses to commit. Best-effort here (the decline itself
      // must not fail on it); the expiry sweep is the backstop.
      if (currentStatus === JOIN_REQUEST_AWAITING_GUARDIAN_STATUS) {
        try {
          const liveConsentRequests = await db
            .collection(CONSENT_REQUESTS_COLLECTION)
            .where("familyId", "==", familyId)
            .where("childUserId", "==", requestData.userId)
            .where("status", "==", "pending")
            .limit(5)
            .get();
          for (const consentDoc of liveConsentRequests.docs) {
            batch.update(consentDoc.ref, {
              status: "superseded",
              resolvedAtMillis: Date.now(),
              guardianEmail: admin.firestore.FieldValue.delete(),
            });
          }
        } catch (error) {
          functions.logger.error(
            "consent-request cancellation on decline failed; expiry sweep will retire it",
            { familyId, requestId, error }
          );
        }
      }

      // FR-88, AND THE BUG THIS WHOLE FIELD EXISTS FOR. A decline used to clear nothing on
      // the child's side: the device's "waiting for your family's approval" flag is cleared
      // only when the child stops being a restricted unconsented child (i.e. approved) or
      // when the identity detaches (i.e. the account was deleted). FR-60(c) deliberately
      // does NOT delete a child with `wasEverInFamily === true`, so a declined sticky child
      // kept a captain deliberating in perpetuity over a request that had already been
      // refused — and could not check, because `families/{id}/pending` is member-read-only.
      //
      // Same batch as the status flip. Guarded on existence only: `batch.update` on a
      // missing doc fails the WHOLE batch, and declining a row whose account is already gone
      // has to stay the idempotent success F-44 made it. The read is one document and only
      // on the decline branch — approve already holds `targetUserDoc`.
      const declinedUserDoc = await db
        .collection("users")
        .doc(requestData.userId)
        .get();
      if (declinedUserDoc.exists) {
        // THE MIRROR of the approve branch's cross-family retirement, and deliberately NOT
        // the same act. A decline refuses consent in THIS family and says nothing whatsoever
        // about another: a child who entered two codes still has a second captain genuinely
        // deliberating, and that request stays live and approvable. Nothing outside this
        // family is retired here.
        //
        // But there is only ONE stamp, so deleting it would erase family B's live decision
        // from the only document the child can read (FR-12 closes `families/{id}/pending` to
        // non-members) and the "waiting" state they are actually still in would vanish. So it
        // is RE-POINTED at a surviving row rather than cleared — one write to one document
        // either way, and still no path by which the field can claim a decision that is not
        // happening.
        //
        // Scoped to an unconsented child, matching where `respondToFamilyInvite_UserStep`
        // writes it: `ChildFamilyPromptPolicy` resolves pending before its restriction
        // classification, so a stamp on anyone else raises the "ask a parent" banner on a
        // screen that must never show it. Anyone else gets the plain clear.
        const declinedUserData = declinedUserDoc.data() as
          | Record<string, unknown>
          | undefined;
        let pendingStampValue: unknown = admin.firestore.FieldValue.delete();
        if (isUnconsentedChildUserData(declinedUserData)) {
          const survivors = await findLivePendingJoinRequestsInOtherFamilies(db, {
            userId: requestData.userId,
            excludeFamilyId: familyId,
          });
          const survivor = survivors.rows[0];
          const survivingFamilyId = survivor ? pendingRowFamilyId(survivor) : null;
          if (survivor && survivingFamilyId) {
            // Any survivor will do: PRESENCE is the whole signal and the payload drives no
            // rule. Its own `createdAt` where readable, so the stamp keeps describing when
            // that request was made rather than when this unrelated decline landed.
            pendingStampValue = buildPendingFamilyRequestStamp({
              familyId: survivingFamilyId,
              requestId: survivor.id,
              createdAt:
                survivor.data()?.createdAt ??
                admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }
        batch.update(db.collection("users").doc(requestData.userId), {
          [PENDING_FAMILY_REQUEST_FIELD]: pendingStampValue,
        });
      }

      // F-44: and every duplicate row for the same user, in the same batch. Here "declined"
      // IS the truth for all of them — consent was refused for this child, once, and the
      // rows are copies of one request. This is also what makes the FR-60(c) cleanup below
      // correct: it runs after the commit, so no live row survives to be stranded by it.
      for (const duplicate of duplicateRequests) {
        batch.update(duplicate.ref, {
          status: "declined",
          resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const matchingInvites = await db
        .collection("invites")
        .where("familyId", "==", familyId)
        .where("toUserId", "==", requestData.userId)
        .where("type", "==", "family")
        .where("status", "==", "accepted")
        .limit(5)
        .get();

      for (const inviteDoc of matchingInvites.docs) {
        batch.update(inviteDoc.ref, {
          status: "declined",
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await writeAuditLog({
        eventType: "family_join_request_declined",
        actorId: userId,
        subjectType: "family",
        subjectId: familyId,
        metadata: {
          requestId,
          userId: requestData.userId,
          declinedInviteCount: matchingInvites.size,
          duplicateRequestCount: duplicateRequests.length,
        },
        clientMetadata,
      });
    }

    await batch.commit();

    // Push AFTER the commit, and never fatal.
    //
    // This used to run inside the approve branch, before `batch.commit()`, with no catch —
    // so `admin.messaging().send()` rejecting a stale token (`registration-token-not-
    // registered`, which is exactly what a child's device holds after the account behind it
    // was deleted and re-provisioned) aborted the ENTIRE approval. Nothing committed, the row
    // stayed pending, and every retry failed identically: an unapprovable request produced by
    // a notification. Worse for the timeout the owner saw — the Admin SDK retries FCM with
    // backoff, so a slow send held the whole callable open past the client's deadline while
    // the membership grant sat uncommitted in memory.
    //
    // Notifying is a courtesy; admission is the decision. It goes last, and it cannot undo it.
    if (response === "approve") {
      try {
        const fcmToken = await getFCMTokenForSocialPush(
          requestData.userId,
          "family"
        );
        if (fcmToken) {
          await sendPushNotification(
            fcmToken,
            "Family Request Approved",
            "You've been approved to join the family",
            {
              type: "family_join_approved",
              familyId,
              deepLink: `roadtrip-royale://family/${familyId}`,
            }
          );
        }
      } catch (error) {
        functions.logger.error(
          "family_join_approved push failed; approval already committed",
          { newMemberId: requestData.userId, familyId, error }
        );
      }
    }

    // COPPA FR-4/FR-25 follow-ons (non-atomic, idempotent; the F-5b syncer exclusion is
    // the purge backstop). Runs only after the membership batch has committed.
    if (childFollowUp?.kind === "grant") {
      const membersSnapshot = await db
        .collection(`families/${familyId}/members`)
        .get();
      const cleanup = await applyChildProtectionsAfterFlagSet(db, {
        childUserId: requestData.userId,
        familyMemberIds: membersSnapshot.docs.map((doc) => doc.id),
        childUserData: childFollowUp.targetUserData,
      });

      await writeChildConsentGranted(db, {
        familyId,
        childUserId: requestData.userId,
        actorId: userId,
        actorRole: memberRole,
        method: "family_admission",
        expectedAgeOutYear: childFollowUp.expectedAgeOutYear,
        removedFriendEdgeCount: cleanup.removedFriendEdgeCount,
        clientMetadata,
      });
    } else if (childFollowUp?.kind === "clear_new_guardian") {
      // FR-25: new guardian explicitly declared not-a-child. Flag already cleared in the
      // batch; search indexes rebuild via the normal profile-sync triggers.
      //
      // FR-66(b): the row now records the manager's ENUMERATED reason rather than a fixed
      // `new_guardian_cleared` slug. No information is lost — `method` already identifies
      // this as the re-admission path — and the audit gains the evidence the gate demands.
      await writeChildConsentCorrected(db, {
        familyId,
        childUserId: requestData.userId,
        actorId: userId,
        actorRole: memberRole,
        method: "readmission_declaration",
        reason: childFollowUp.correctionReason,
        clientMetadata,
      });
    }

    // COPPA FR-60(c): a declined request from a NEVER-CONSENTED provisional child ends that
    // account outright. Under the local-first model the uid exists only because the child
    // entered a share code; a decline means consent was refused, so the transient server
    // footprint has no basis to persist. The device keeps its age answer and ratchet, so a
    // later code entry re-provisions cleanly as a child.
    //
    // The helper re-reads the user doc and is a no-op for anyone else — an adult, a
    // consented child, and (critically) a STICKY POST-REVOCATION child, who keeps the FR-28
    // restricted state and the OD-3 window. See `provisionalChildAccounts.ts`.
    //
    // F-44, and the reason this sits AFTER `batch.commit()` rather than beside the decline:
    // the helper now refuses to delete an account that still holds a pending join request
    // anywhere. The batch above declined this row AND every duplicate of it, so by the time
    // we get here there is none left and the deletion proceeds — but if the child also has a
    // live request in some OTHER family, the helper leaves the account alone and that
    // captain's queue stays answerable. It is also what makes the approve branch safe by
    // construction: an approved child has `activeFamilyId` and `wasEverInFamily` from the
    // same batch, so the predicate excludes them even if this ever ran on that path.
    //
    // Deliberately non-fatal: the decline itself has already committed. A failure here leaves
    // the account for the FR-77 seven-day backstop sweep, which exists for exactly this case,
    // and re-invoking the callable is now an idempotent success rather than an error.
    if (response === "decline") {
      try {
        await deleteProvisionalChildAccountIfNeverConsented(db, {
          userId: requestData.userId,
          actorId: userId,
          clientMetadata,
          revenueCatApiKey: currentRevenueCatApiKey(),
        });
      } catch (error) {
        functions.logger.error(
          "FR-60(c): provisional child cleanup after decline failed; backstop sweep will retry",
          { childUserId: requestData.userId, error }
        );
      }
    }

    return { success: true };
  }
);

/**
 * Remove a family member
 */
export const removeFamilyMember = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, memberId } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !memberId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId and memberId are required"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;

    // Get member to remove
    const targetMemberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(memberId)
      .get();

    if (!targetMemberDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Member not found");
    }

    const targetMemberRole = targetMemberDoc.data()!.role;
    // COPPA FR-6: detect the child projection BEFORE the member doc is deleted.
    const targetWasChild = targetMemberDoc.data()!.isChild === true;
    const isSelf = memberId === userId;
    const decision = canRemoveFamilyMember({
      actorRole: memberRole,
      targetRole: targetMemberRole,
      isSelf,
    });
    if (!decision.allowed) {
      throw new functions.https.HttpsError(decision.code, decision.message);
    }

    const batch = db.batch();

    // Remove member
    batch.delete(targetMemberDoc.ref);

    // Clear activeFamilyId if not retired general; sticky-flag for legacy members
    const userDoc = await db.collection("users").doc(memberId).get();
    const userData = userDoc.data();
    if (userData) {
      batch.update(
        db.collection("users").doc(memberId),
        familyMembershipLeaveUserUpdate({
          isRetiredGeneral: !!userData.isRetiredGeneral,
        })
      );
    }

    await batch.commit();

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_MEMBER_REMOVED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: { removedMemberId: memberId, role: targetMemberRole },
      clientMetadata,
    });

    // COPPA FR-6: a flagged child's membership just ended — consent is revoked, the
    // sticky `isChildAccount` flag is untouched (protection persists, collection stops).
    if (targetWasChild) {
      await writeChildMembershipRevocation(db, {
        familyId,
        childUserId: memberId,
        actorId: userId,
        actorRole: isSelf ? targetMemberRole : memberRole,
        method: "remove_family_member",
        reason: isSelf ? "member_left_family" : "parent_removed_child",
        clientMetadata,
      });
    }

    return { success: true };
  }
);

/**
 * Change a family member's role
 */
export const changeFamilyMemberRole = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId, memberId, newRole } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId || !memberId || !newRole) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId, memberId, and newRole are required"
      );
    }

    // Verify user is creator or captain
    const memberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(userId)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a family member"
      );
    }

    const memberRole = memberDoc.data()!.role;
    if (memberRole !== "creator" && memberRole !== "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Captains can change roles"
      );
    }

    // MVP: Only allow scout <-> sergeant changes
    // Captain assignment and creator changes not included in MVP
    if (newRole !== "scout" && newRole !== "sergeant") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "MVP only supports scout and sergeant roles"
      );
    }

    // Get target member
    const targetMemberDoc = await db
      .collection(`families/${familyId}/members`)
      .doc(memberId)
      .get();

    if (!targetMemberDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Member not found");
    }

    const currentRole = targetMemberDoc.data()!.role;

    // Can't change creator or captain roles in MVP
    if (currentRole === "creator" || currentRole === "captain") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Cannot change Captain roles"
      );
    }

    // Update role
    await targetMemberDoc.ref.update({
      role: newRole,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_ROLE_CHANGED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: { memberId, oldRole: currentRole, newRole },
      clientMetadata,
    });

    return { success: true };
  }
);

/**
 * Inactivate a family (creator only)
 * Marks family as inactive, removes all members, and clears activeFamilyId
 */
export const inactivateFamily = enforcedCallable(
  async (data, context) => {
    const userId = assertRegisteredAccount(context);

    const { familyId } = data;
    const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

    if (!familyId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "familyId is required"
      );
    }

    // Verify user is the creator
    const familyDoc = await db.collection("families").doc(familyId).get();
    if (!familyDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Family not found");
    }

    const familyData = familyDoc.data()!;
    if (familyData.creatorId !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the Captain who created the family can delete it"
      );
    }

    // Verify family is active
    if (familyData.status !== "active") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Family is already inactive"
      );
    }

    const batch = db.batch();

    // Mark family as inactive
    batch.update(familyDoc.ref, {
      status: "inactive",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Get all members
    const membersSnapshot = await db
      .collection(`families/${familyId}/members`)
      .get();

    // FR-88: a family that stops existing stops deciding. Undecided join requests used to be
    // simply ORPHANED here — the row survived in a subcollection nobody would ever open
    // again, and the requester (a child, in the case that matters) kept the "waiting for your
    // family's approval" state with no captain left to end it. That is the same stranding the
    // decline branch above fixes, arriving by a different door, so it is closed the same way:
    // the rows go terminal and every requester's server stamp goes with them, in this batch.
    //
    // `expired`, not `declined`: no consent decision was ever made, and F-44 already uses
    // exactly this status for a row retired without one. Deliberately no FR-60(c) account
    // cleanup — with no live row left, the FR-77 backstop sweep can now reach a
    // never-consented account on its own schedule, which is the path that exists for it.
    //
    // Resolved BEFORE the member loop so the two can be folded into ONE write per user doc.
    // A commit carrying two writes for the same document is rejected outright, and both
    // collisions are reachable on legacy data: F-44 duplicate rows for one uid, and a row
    // left live beside a membership that was granted on its sibling.
    const orphanedRequests = await db
      .collection(`families/${familyId}/pending`)
      .where("status", "==", JOIN_REQUEST_PENDING_STATUS)
      .get();

    const orphanedRequesterIds = new Set<string>();
    for (const requestDoc of orphanedRequests.docs) {
      batch.update(requestDoc.ref, {
        status: JOIN_REQUEST_SUPERSEDED_STATUS,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const requesterId = requestDoc.data()?.userId;
      if (typeof requesterId === "string" && requesterId.length > 0) {
        orphanedRequesterIds.add(requesterId);
      }
    }

    // COPPA FR-6: capture flagged children BEFORE their member docs are deleted.
    const childMemberIds: string[] = [];

    // Remove all members and clear activeFamilyId
    for (const memberDoc of membersSnapshot.docs) {
      const memberId = memberDoc.id;

      if (memberDoc.data()?.isChild === true) {
        childMemberIds.push(memberId);
      }

      // Remove member
      batch.delete(memberDoc.ref);

      // Clear activeFamilyId if not retired general; sticky-flag for legacy members
      const userDoc = await db.collection("users").doc(memberId).get();
      const userData = userDoc.data();
      if (userData) {
        const leaveUpdate: Record<string, unknown> = familyMembershipLeaveUserUpdate({
          isRetiredGeneral: !!userData.isRetiredGeneral,
        });
        if (orphanedRequesterIds.delete(memberId)) {
          leaveUpdate[PENDING_FAMILY_REQUEST_FIELD] =
            admin.firestore.FieldValue.delete();
        }
        batch.update(db.collection("users").doc(memberId), leaveUpdate);
      } else {
        // No user doc to write to at all, membership or otherwise.
        orphanedRequesterIds.delete(memberId);
      }
    }

    // Whatever is left is a requester who never became a member. `batch.update` on a missing
    // doc fails the whole batch, so the existence check is not optional.
    for (const requesterId of orphanedRequesterIds) {
      const requesterDoc = await db.collection("users").doc(requesterId).get();
      if (requesterDoc.exists) {
        batch.update(db.collection("users").doc(requesterId), {
          [PENDING_FAMILY_REQUEST_FIELD]: admin.firestore.FieldValue.delete(),
        });
      }
    }

    await batch.commit();

    // COPPA FR-6: every flagged child's membership ended with the family; consent is
    // revoked while the sticky `isChildAccount` flag stays true.
    for (const childUserId of childMemberIds) {
      await writeChildMembershipRevocation(db, {
        familyId,
        childUserId,
        actorId: userId,
        actorRole: "creator",
        method: "inactivate_family",
        reason: "family_inactivated",
        clientMetadata,
      });
    }

    await writeAuditLog({
      eventType: "AUDIT_FAMILY_INACTIVATED",
      actorId: userId,
      subjectType: "family",
      subjectId: familyId,
      metadata: {
        reason: "creator_inactivated",
        familyNameHash: auditValueHash(familyData.name),
      },
      clientMetadata,
    });

    return { success: true };
  }
);

