/**
 * FR-61 (F-19) — the parental review right returns ACTUAL data.
 *
 * `buildChildDataInventoryFlow` assembles, server-side, an inventory of everything this
 * project holds for one child uid, gated by the same durable-guardianship authorizer the
 * deletion right uses (FR-62): a live manager authorizes, else the recorded guardian —
 * review survives the child's removal. Rules stay closed; every read happens here via the
 * Admin SDK.
 *
 * PARITY DISCIPLINE (the FR-61 acceptance criterion): if deletion knows about a data
 * location, review must too. `PER_UID_DATA_LOCATION_KEYS` is the single manifest; the
 * builder's section map is typed `Record<PerUidDataLocationKey, …>` so a key added to the
 * manifest without an inventory section is a COMPILE error, and the parity test
 * (`childDataInventory.test.ts`) asserts the manifest matches `DELETION_SWEEP_LOCATION_KEYS`
 * declared beside the sweep in `accountDeletion.ts`.
 *
 * Response discipline: the payload carries the CHILD'S OWN data (that is what §312.6(a)(3)
 * review means) and never another user's identifiers — trip summaries carry trip fields
 * only, friend edges are counted not named, and contact identifiers are reported as
 * presence booleans, never values.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { authorizeParentalRights } from "./familyChildStatusFlows";
import { discoverAffectedSessionIds } from "./accountDeletionDeidentify";
import { currentRevenueCatApiKey } from "./accountDeletion";
import { searchIndexHintsForUser } from "./userResidueCleanup";
import {
  COLLECTION_LOOKUP_EMAIL,
  COLLECTION_LOOKUP_PHONE,
  COLLECTION_USERNAMES,
  PRIVATE_CONTACT_DOC,
} from "./userSearchIndex";
import {
  INVITE_RATE_LIMIT_COLLECTION,
  inviteRateLimitDocIdsForUser,
} from "./inviteRateLimitCore";
import { LOCATION_PAYLOAD_KEYS } from "./payloadKeys";
import { phoneLookupDocId } from "./userSearchCore";

type Firestore = admin.firestore.Firestore;

/**
 * The manifest: every per-uid data location this project holds. One entry per location
 * the deletion sweep (`executeAccountDeletionForUser`) touches, plus the two vendor
 * footprints its FR-78 phases cover. Adding a location to the sweep without adding it
 * here fails the parity test; adding it here without an inventory section fails to
 * compile.
 */
export const PER_UID_DATA_LOCATION_KEYS = [
  "user_profile",
  "private_subcollection",
  "search_indexes",
  "friend_edges",
  "family_membership",
  "progression",
  "achievements",
  "public_lifetime_stats",
  "invite_rate_limits",
  "gameplay_residue",
  "revenuecat_vendor",
  "analytics_vendor",
] as const;

export type PerUidDataLocationKey = (typeof PER_UID_DATA_LOCATION_KEYS)[number];

/** Sessions summarized per response; anything beyond is counted, never hidden. */
export const INVENTORY_SESSION_SUMMARY_CAP = 50;

function millisFromTimestampLike(value: unknown): number | null {
  if (
    value &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}

export interface ChildTripSummary {
  tripName: string | null;
  status: string | null;
  createdAtMillis: number | null;
  endedAtMillis: number | null;
  authoredEventCountsByKind: Record<string, number>;
  attributedEventCount: number;
  anyLocationPayload: boolean;
}

export interface ChildDataInventoryResult {
  accountExists: boolean;
  isChildAccount: boolean;
  viaGuardianship: boolean;
  generatedAtMillis: number;
  sections: Record<PerUidDataLocationKey, Record<string, unknown>>;
}

function emptySections(): Record<PerUidDataLocationKey, Record<string, unknown>> {
  const sections = {
    user_profile: { present: false },
    private_subcollection: { present: false },
    search_indexes: { present: false },
    friend_edges: { present: false, edgeCount: 0 },
    family_membership: { present: false },
    progression: { present: false },
    achievements: { present: false },
    public_lifetime_stats: { present: false },
    invite_rate_limits: { present: false, counterCount: 0 },
    gameplay_residue: { present: false, sessionCount: 0 },
    // Vendor postures are true even for a deleted account: they describe the
    // project's standing FR-78 arrangement, not per-child state.
    revenuecat_vendor: {
      present: false,
      configured: currentRevenueCatApiKey() !== null,
      posture: "deleted_with_account",
    },
    analytics_vendor: {
      present: false,
      posture: "no_uid_in_catalog_client_reset_on_deletion",
    },
  } satisfies Record<PerUidDataLocationKey, Record<string, unknown>>;
  return sections;
}

/**
 * FR-61: assemble the live inventory for one child uid. Authorization identical to
 * `requestChildDataDeletion` / `getParentalConsentStatus` (FR-62 ladder). For a child
 * whose account was already deleted, the honest §312.6 answer is an inventory of
 * nothing — the recorded guardian still authorizes, `accountExists` is false, and every
 * section reports absent — never an error.
 */
export async function buildChildDataInventoryFlow(
  db: Firestore,
  input: { actorId: string; familyId: string; childUserId: string }
): Promise<ChildDataInventoryResult> {
  const { actorId, familyId, childUserId } = input;

  const { viaGuardianship } = await authorizeParentalRights(db, {
    actorId,
    familyId,
    childUserId,
  });

  const userRef = db.collection("users").doc(childUserId);
  const userDoc = await userRef.get();
  const sections = emptySections();

  if (!userDoc.exists) {
    return {
      accountExists: false,
      isChildAccount: false,
      viaGuardianship,
      generatedAtMillis: Date.now(),
      sections,
    };
  }

  const userData = userDoc.data() ?? {};
  if (userData.isChildAccount !== true) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This member is not marked as a child"
    );
  }

  // ---- user_profile (users/{uid} fields; contact values NEVER appear here)
  sections.user_profile = {
    present: true,
    userName: typeof userData.userName === "string" ? userData.userName : null,
    avatarId: typeof userData.avatarId === "string" ? userData.avatarId : null,
    isChildAccount: true,
    ageOutYearMonth:
      typeof userData.ageOutYearMonth === "number" ? userData.ageOutYearMonth : null,
    wasEverInFamily: userData.wasEverInFamily === true,
    createdAtMillis: millisFromTimestampLike(userData.createdAt),
    lastDateLoggedInMillis: millisFromTimestampLike(userData.lastDateLoggedIn),
    childDeclaredAtMillis: millisFromTimestampLike(userData.childDeclaredAt),
  };

  // ---- private_subcollection (contact/fcm/guardianship/…): presence, never values
  const privateDocs = await userRef.collection("private").listDocuments();
  const privateIds = privateDocs.map((ref) => ref.id).sort();
  const privateSection: Record<string, unknown> = {
    present: privateIds.length > 0,
    documentIds: privateIds,
  };
  if (privateIds.includes(PRIVATE_CONTACT_DOC)) {
    const contact = (await userRef.collection("private").doc(PRIVATE_CONTACT_DOC).get()).data();
    privateSection.contact = {
      hasEmail: typeof contact?.email === "string" && contact.email.length > 0,
      hasPhoneNumber:
        typeof contact?.phoneNumber === "string" && contact.phoneNumber.length > 0,
    };
  }
  if (privateIds.includes("fcm")) {
    const fcm = (await userRef.collection("private").doc("fcm").get()).data();
    privateSection.pushTokenPresent =
      typeof fcm?.token === "string" && fcm.token.length > 0;
  } else {
    privateSection.pushTokenPresent = false;
  }
  if (privateIds.includes("guardianship")) {
    const guardianship = (
      await userRef.collection("private").doc("guardianship").get()
    ).data();
    privateSection.guardianship = {
      grantedAtMillis: millisFromTimestampLike(guardianship?.grantedAt),
      endedAtMillis:
        typeof guardianship?.endedAtMillis === "number" ? guardianship.endedAtMillis : null,
      endedReason:
        typeof guardianship?.endedReason === "string" ? guardianship.endedReason : null,
    };
  }
  sections.private_subcollection = privateSection;

  // ---- search_indexes: for a child every row must already be absent (FR-11) — the
  // inventory REPORTS that rather than assuming it.
  const hints = await searchIndexHintsForUser(db, childUserId, userData);
  const usernameRow = hints.userNameLower
    ? await db.collection(COLLECTION_USERNAMES).doc(hints.userNameLower).get()
    : null;
  const emailRow = hints.emailLower
    ? await db.collection(COLLECTION_LOOKUP_EMAIL).doc(hints.emailLower).get()
    : null;
  const phoneRow = hints.phoneE164
    ? await db.collection(COLLECTION_LOOKUP_PHONE).doc(phoneLookupDocId(hints.phoneE164)).get()
    : null;
  const usernameIndexed = usernameRow?.exists === true && usernameRow.data()?.userId === childUserId;
  const emailIndexed = emailRow?.exists === true && emailRow.data()?.userId === childUserId;
  const phoneIndexed = phoneRow?.exists === true && phoneRow.data()?.userId === childUserId;
  sections.search_indexes = {
    present: usernameIndexed || emailIndexed || phoneIndexed,
    usernameIndexed,
    emailIndexed,
    phoneIndexed,
  };

  // ---- friend_edges: counted, never named (the other side is someone else's data)
  const [edgesAsA, edgesAsB] = await Promise.all([
    db.collection("friends").where("userA", "==", childUserId).get(),
    db.collection("friends").where("userB", "==", childUserId).get(),
  ]);
  const edgeCount = edgesAsA.size + edgesAsB.size;
  sections.friend_edges = { present: edgeCount > 0, edgeCount };

  // ---- family_membership
  const memberDoc = await db
    .collection(`families/${familyId}/members`)
    .doc(childUserId)
    .get();
  sections.family_membership = memberDoc.exists
    ? {
        present: true,
        role: typeof memberDoc.data()?.role === "string" ? memberDoc.data()?.role : null,
        isChild: memberDoc.data()?.isChild === true,
        consentPending: memberDoc.data()?.consentPending === true,
      }
    : { present: false };

  // ---- progression (+ xp_grants ledger)
  const progressionRef = db.collection("user_progression").doc(childUserId);
  const progressionDoc = await progressionRef.get();
  const xpGrantRefs = await progressionRef.collection("xp_grants").listDocuments();
  sections.progression = {
    present: progressionDoc.exists || xpGrantRefs.length > 0,
    totalXp:
      typeof progressionDoc.data()?.totalXp === "number" ? progressionDoc.data()?.totalXp : null,
    level:
      typeof progressionDoc.data()?.level === "number" ? progressionDoc.data()?.level : null,
    xpGrantCount: xpGrantRefs.length,
  };

  // ---- achievements
  const achievementsRef = db.collection("user_achievements").doc(childUserId);
  const achievementsDoc = await achievementsRef.get();
  const achievementRefs = await achievementsRef.collection("achievements").listDocuments();
  sections.achievements = {
    present: achievementsDoc.exists || achievementRefs.length > 0,
    unlockedCount: achievementRefs.length,
  };

  // ---- public_lifetime_stats: numeric totals only, exactly as published
  const statsDoc = await db.collection("public_lifetime_stats").doc(childUserId).get();
  const statsData = statsDoc.data() ?? {};
  const numericStats: Record<string, number> = {};
  for (const [key, value] of Object.entries(statsData)) {
    if (typeof value === "number") numericStats[key] = value;
  }
  sections.public_lifetime_stats = { present: statsDoc.exists, totals: numericStats };

  // ---- invite_rate_limits: uid-keyed operational counters (FR-47)
  const rateLimitDocs = await Promise.all(
    inviteRateLimitDocIdsForUser(childUserId).map((docId) =>
      db.collection(INVITE_RATE_LIMIT_COLLECTION).doc(docId).get()
    )
  );
  const counterCount = rateLimitDocs.filter((doc) => doc.exists).length;
  sections.invite_rate_limits = { present: counterCount > 0, counterCount };

  // ---- gameplay_residue: per-trip participation, event category counts, and whether
  // any stored event still carries a location payload (FR-33/FR-76 verification value).
  const sessionIds = await discoverAffectedSessionIds(db, childUserId);
  const [authoredSnap, attributedSnap, invitesFromSnap, invitesToSnap, shareCodesSnap, buffersSnap] =
    await Promise.all([
      db.collectionGroup("activity_events").where("actorId", "==", childUserId).get(),
      db
        .collectionGroup("activity_events")
        .where("payload.participantId", "==", childUserId)
        .get(),
      db.collection("trip_invites").where("fromUserId", "==", childUserId).get(),
      db.collection("trip_invites").where("toUserId", "==", childUserId).get(),
      db.collection("share_codes").where("createdBy", "==", childUserId).get(),
      db.collection("plate_found_notify_buffers").where("recipientUid", "==", childUserId).get(),
    ]);

  const authoredBySession = new Map<string, { byKind: Record<string, number>; anyLocation: boolean }>();
  let anyLocationPayloadExists = false;
  for (const doc of authoredSnap.docs) {
    const sessionId = doc.ref.parent.parent?.id;
    if (!sessionId) continue;
    const entry =
      authoredBySession.get(sessionId) ?? { byKind: {}, anyLocation: false };
    const kind = typeof doc.data()?.kind === "string" ? (doc.data()?.kind as string) : "unknown";
    entry.byKind[kind] = (entry.byKind[kind] ?? 0) + 1;
    const payload = (doc.data()?.payload ?? {}) as Record<string, unknown>;
    if (LOCATION_PAYLOAD_KEYS.some((key) => payload[key] !== undefined)) {
      entry.anyLocation = true;
      anyLocationPayloadExists = true;
    }
    authoredBySession.set(sessionId, entry);
  }
  const attributedBySession = new Map<string, number>();
  for (const doc of attributedSnap.docs) {
    const sessionId = doc.ref.parent.parent?.id;
    if (!sessionId) continue;
    attributedBySession.set(sessionId, (attributedBySession.get(sessionId) ?? 0) + 1);
  }

  const summarizedIds = sessionIds.slice(0, INVENTORY_SESSION_SUMMARY_CAP);
  const trips: ChildTripSummary[] = [];
  for (const sessionId of summarizedIds) {
    const sessionDoc = await db.collection("trip_sessions").doc(sessionId).get();
    const sessionData = sessionDoc.data() ?? {};
    const authored = authoredBySession.get(sessionId);
    trips.push({
      tripName: typeof sessionData.name === "string" ? sessionData.name : null,
      status: typeof sessionData.status === "string" ? sessionData.status : null,
      createdAtMillis: millisFromTimestampLike(sessionData.createdAt),
      endedAtMillis: millisFromTimestampLike(sessionData.endedAt),
      authoredEventCountsByKind: authored?.byKind ?? {},
      attributedEventCount: attributedBySession.get(sessionId) ?? 0,
      anyLocationPayload: authored?.anyLocation ?? false,
    });
  }

  sections.gameplay_residue = {
    present:
      sessionIds.length > 0 ||
      authoredSnap.size > 0 ||
      invitesFromSnap.size + invitesToSnap.size > 0 ||
      shareCodesSnap.size > 0 ||
      buffersSnap.size > 0,
    sessionCount: sessionIds.length,
    summarizedSessionCount: summarizedIds.length,
    truncated: sessionIds.length > summarizedIds.length,
    trips,
    authoredEventTotal: authoredSnap.size,
    attributedEventTotal: attributedSnap.size,
    anyLocationPayloadExists,
    tripInvitesSent: invitesFromSnap.size,
    tripInvitesReceived: invitesToSnap.size,
    shareCodesCreated: shareCodesSnap.size,
    pendingNotifyBufferCount: buffersSnap.size,
  };

  // ---- vendor footprints (FR-78): standing postures, described honestly
  sections.revenuecat_vendor = {
    present: false,
    configured: currentRevenueCatApiKey() !== null,
    posture: "deleted_with_account",
  };
  sections.analytics_vendor = {
    present: false,
    posture: "no_uid_in_catalog_client_reset_on_deletion",
  };

  return {
    accountExists: true,
    isChildAccount: true,
    viaGuardianship,
    generatedAtMillis: Date.now(),
    sections,
  };
}

export interface GuardedChildRow {
  childUserId: string;
  familyId: string;
  childUserName: string | null;
  accountExists: boolean;
  grantedAtMillis: number | null;
  endedAtMillis: number | null;
  endedReason: string | null;
}

/**
 * FR-61 ex-member entry point (FR-62's deferred device check): the children this actor
 * is the RECORDED guardian for, live or ended — the feed behind "children you've
 * consented for". Collection-group query on the guardianship docs (the only `private`
 * docs carrying `guardianUid`; index override beside `private`/`userId`'s).
 */
export async function listGuardedChildrenFlow(
  db: Firestore,
  input: { actorId: string }
): Promise<{ children: GuardedChildRow[] }> {
  const snap = await db
    .collectionGroup("private")
    .where("guardianUid", "==", input.actorId)
    .get();

  const rows: GuardedChildRow[] = [];
  for (const doc of snap.docs) {
    if (doc.id !== "guardianship") continue;
    const childUserId = doc.ref.parent.parent?.id;
    if (!childUserId) continue;
    const data = doc.data() ?? {};
    const childUserDoc = await db.collection("users").doc(childUserId).get();
    rows.push({
      childUserId,
      familyId: typeof data.familyId === "string" ? data.familyId : "",
      childUserName:
        typeof childUserDoc.data()?.userName === "string"
          ? (childUserDoc.data()?.userName as string)
          : null,
      accountExists: childUserDoc.exists,
      grantedAtMillis: millisFromTimestampLike(data.grantedAt),
      endedAtMillis: typeof data.endedAtMillis === "number" ? data.endedAtMillis : null,
      endedReason: typeof data.endedReason === "string" ? data.endedReason : null,
    });
  }
  rows.sort((a, b) => (b.grantedAtMillis ?? 0) - (a.grantedAtMillis ?? 0));
  return { children: rows };
}
