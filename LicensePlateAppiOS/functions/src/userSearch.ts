import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { enforcedCallable } from "./callableOptions";
import { assertRegisteredAccount } from "./callableAuth";
import { normalizeClientMetadata } from "./clientMetadata";
import { writeAuditLog } from "./audit";
import {
  auditQueryFingerprint,
  classifySearchQuery,
  isSearchIndexEligible,
  normalizeEmail,
  normalizePhoneE164,
  normalizeUsernameLower,
  phoneLookupDocId,
  toPublicSearchHit,
  type PublicSearchHit,
  type SearchMatchField,
} from "./userSearchCore";
import {
  COLLECTION_LOOKUP_EMAIL,
  COLLECTION_LOOKUP_PHONE,
  COLLECTION_USERNAMES,
  buildContactFields,
  syncContactLookupIndexes,
  syncUsernameSearchIndex,
  PRIVATE_CONTACT_DOC,
} from "./userSearchIndex";
import { isUserSearchable } from "./utils/validation";
import { isChildAccountUserData } from "./childAccountCore";
import { searchIndexHintsForUser } from "./userResidueCleanup";

const db = admin.firestore();

async function loadUserHit(
  userId: string,
  matchedField: SearchMatchField,
  excludeUserId: string
): Promise<PublicSearchHit | null> {
  if (!userId || userId === excludeUserId) return null;
  const snap = await db.collection("users").doc(userId).get();
  if (!snap.exists) return null;
  return toPublicSearchHit(userId, snap.data() || {}, matchedField);
}

async function searchByEmail(
  query: string,
  callerId: string
): Promise<PublicSearchHit[]> {
  const emailLower = normalizeEmail(query);
  const lookup = await db
    .collection(COLLECTION_LOOKUP_EMAIL)
    .doc(emailLower)
    .get();
  if (!lookup.exists) return [];
  const userId = lookup.data()?.userId as string | undefined;
  if (!userId) return [];
  // Honor isEmailPublic / privacy.emailSearchable at query time (real-time).
  if (!(await isUserSearchable(userId, "email"))) return [];
  const hit = await loadUserHit(userId, "email", callerId);
  return hit ? [hit] : [];
}

async function searchByPhone(
  query: string,
  callerId: string
): Promise<PublicSearchHit[]> {
  const e164 = normalizePhoneE164(query);
  if (!e164) return [];
  const lookup = await db
    .collection(COLLECTION_LOOKUP_PHONE)
    .doc(phoneLookupDocId(e164))
    .get();
  if (!lookup.exists) return [];
  const userId = lookup.data()?.userId as string | undefined;
  if (!userId) return [];
  // Honor isPhonePublic / privacy.phoneSearchable at query time (real-time).
  if (!(await isUserSearchable(userId, "phone"))) return [];
  const hit = await loadUserHit(userId, "phone", callerId);
  return hit ? [hit] : [];
}

async function searchByUsername(
  query: string,
  callerId: string
): Promise<PublicSearchHit[]> {
  const q = normalizeUsernameLower(query);
  const results: PublicSearchHit[] = [];
  const seen = new Set<string>();

  // Exact via usernames index
  const unameSnap = await db.collection(COLLECTION_USERNAMES).doc(q).get();
  if (unameSnap.exists) {
    const userId = unameSnap.data()?.userId as string | undefined;
    if (userId) {
      const hit = await loadUserHit(userId, "username", callerId);
      if (hit) {
        results.push(hit);
        seen.add(hit.userId);
      }
    }
  }

  // Exact via userNameLower field (fallback)
  if (results.length === 0) {
    const exact = await db
      .collection("users")
      .where("userNameLower", "==", q)
      .limit(5)
      .get();
    for (const doc of exact.docs) {
      const hit = await loadUserHit(doc.id, "username", callerId);
      if (hit && !seen.has(hit.userId)) {
        results.push(hit);
        seen.add(hit.userId);
      }
    }
  }

  // Prefix
  const prefixSnap = await db
    .collection("users")
    .where("userNameLower", ">=", q)
    .where("userNameLower", "<", q + "\uf8ff")
    .limit(20)
    .get();

  for (const doc of prefixSnap.docs) {
    if (seen.has(doc.id)) continue;
    const hit = toPublicSearchHit(doc.id, doc.data() || {}, "username");
    if (!hit) continue;
    if (hit.userId === callerId) continue;
    results.push(hit);
    seen.add(hit.userId);
    if (results.length >= 20) break;
  }

  return results;
}

/**
 * Registered-account user discovery. Returns public profile fields only.
 */
export const searchUsers = enforcedCallable(async (data, context) => {
  const callerId = assertRegisteredAccount(context);
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);
  const queryRaw = typeof data?.query === "string" ? data.query : "";
  const query = queryRaw.trim();

  if (query.length < 3) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Query must be at least 3 characters"
    );
  }

  const kind = classifySearchQuery(query);
  let results: PublicSearchHit[] = [];

  // FR-24 (COPPA F-5b): a child caller — consented or not — gets zero hits. Returned as a
  // normal empty result set rather than an error so the child's own app instance behaves
  // exactly like an adult's fruitless search (FR-21: no child-only signal on that device);
  // the client hides the entry point entirely (F-6/F-8).
  const callerDoc = await db.collection("users").doc(callerId).get();
  const callerIsChild = isChildAccountUserData(callerDoc.data());

  if (callerIsChild) {
    results = [];
  } else if (kind === "email") {
    results = await searchByEmail(query, callerId);
  } else if (kind === "phone") {
    results = await searchByPhone(query, callerId);
  } else {
    results = await searchByUsername(query, callerId);
  }

  // Defense: never return unregistered (toPublicSearchHit already filters)
  results = results.filter((r) => r.userId && r.userName);

  await writeAuditLog({
    eventType: "user_search_performed",
    actorId: callerId,
    subjectType: "user",
    subjectId: callerId,
    metadata: {
      kind,
      fingerprint: auditQueryFingerprint(kind, query),
      resultCount: results.length,
      queryHash: createHash("sha256").update(query.toLowerCase()).digest("hex").slice(0, 16),
    },
    clientMetadata,
  });

  return { results };
});

/**
 * Keep userNameLower + usernames index in sync; strip lookup indexes when anonymous
 * — or when the account is a child (FR-11: children are indexed exactly like
 * non-registered accounts, i.e. never, and any existing entry is removed).
 */
export const onUserProfileSearchIndexSync = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const before = change.before.exists ? change.before.data() || {} : null;
    const after = change.after.exists ? change.after.data() || {} : null;

    if (!after) {
      // User deleted — clear indexes using before hints
      if (before) {
        const emailLower =
          typeof before.email === "string"
            ? normalizeEmail(before.email)
            : null;
        const phoneE164 =
          typeof before.phoneNumber === "string"
            ? normalizePhoneE164(before.phoneNumber)
            : null;
        await syncUsernameSearchIndex({
          userId,
          userName: null,
          previousUserNameLower:
            (before.userNameLower as string) ||
            (typeof before.userName === "string" ? before.userName : null),
          isRegistered: false,
        });
        await syncContactLookupIndexes({
          userId,
          isRegistered: false,
          contact: buildContactFields(null, null),
          previousEmailLower: emailLower,
          previousPhoneE164: phoneE164,
        });
      }
      return;
    }

    // FR-11: index eligibility now excludes children as well as anonymous accounts. This
    // trigger is the ONE place every `users/{uid}` write funnels through, which is what
    // makes it the backstop behind the FR-4 flag-set purge (child branch below).
    const isIndexEligible = isSearchIndexEligible(after);
    const userName =
      typeof after.userName === "string"
        ? after.userName
        : typeof after.username === "string"
          ? after.username
          : null;
    const previousUserNameLower =
      (before?.userNameLower as string) ||
      (typeof before?.userName === "string"
        ? normalizeUsernameLower(before.userName)
        : null);

    if (isChildAccountUserData(after)) {
      // FR-11 backstop, child branch. Contact identifiers live in `users/{uid}/private/contact`
      // (FR-43), so the generic path below — which only ever sees top-level email/phone —
      // has no key with which to delete a stale `user_lookup_*` row. Resolve the same hints
      // the FR-4 purge uses and delete against those, so a purge that failed (or a child
      // flagged while the purge was mid-flight) is repaired on the very next profile write.
      const hints = await searchIndexHintsForUser(db, userId, after);
      await syncUsernameSearchIndex({
        userId,
        userName,
        previousUserNameLower,
        isRegistered: false,
      });
      await syncContactLookupIndexes({
        userId,
        isRegistered: false,
        contact: buildContactFields(
          typeof after.email === "string" ? after.email : null,
          typeof after.phoneNumber === "string" ? after.phoneNumber : null
        ),
        previousEmailLower: hints.emailLower,
        previousPhoneE164: hints.phoneE164,
      });
      return;
    }

    await syncUsernameSearchIndex({
      userId,
      userName,
      previousUserNameLower,
      isRegistered: isIndexEligible,
    });

    // Dual-write era: public email/phone still on users doc — index from them
    // until private/contact is sole source (contact trigger also runs).
    const contact = buildContactFields(
      typeof after.email === "string" ? after.email : null,
      typeof after.phoneNumber === "string" ? after.phoneNumber : null
    );
    const previousContact = before
      ? buildContactFields(
          typeof before.email === "string" ? before.email : null,
          typeof before.phoneNumber === "string" ? before.phoneNumber : null
        )
      : null;

    if (contact.emailLower || contact.phoneE164 || previousContact) {
      await syncContactLookupIndexes({
        userId,
        isRegistered: isIndexEligible,
        contact,
        previousEmailLower: previousContact?.emailLower,
        previousPhoneE164: previousContact?.phoneE164,
      });
    } else if (!isIndexEligible) {
      await syncContactLookupIndexes({
        userId,
        isRegistered: false,
        contact: buildContactFields(null, null),
      });
    }
  });

/**
 * Maintain email/phone lookup indexes from private/contact.
 * FR-11: children are ineligible here too — otherwise a contact write would re-create the
 * very `user_lookup_*` rows the profile syncer just removed.
 */
export const onUserContactSearchIndexSync = functions.firestore
  .document(`users/{userId}/private/${PRIVATE_CONTACT_DOC}`)
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const userSnap = await db.collection("users").doc(userId).get();
    const userData = userSnap.data() || {};
    const isRegistered = isSearchIndexEligible(userData);

    const before = change.before.exists ? change.before.data() || {} : null;
    const after = change.after.exists ? change.after.data() || {} : null;

    const contact = after
      ? {
          email: typeof after.email === "string" ? after.email : null,
          emailLower:
            typeof after.emailLower === "string"
              ? after.emailLower
              : typeof after.email === "string"
                ? normalizeEmail(after.email)
                : null,
          phoneNumber:
            typeof after.phoneNumber === "string" ? after.phoneNumber : null,
          phoneE164:
            typeof after.phoneE164 === "string"
              ? after.phoneE164
              : typeof after.phoneNumber === "string"
                ? normalizePhoneE164(after.phoneNumber)
                : null,
        }
      : buildContactFields(null, null);

    const previousEmailLower =
      typeof before?.emailLower === "string"
        ? before.emailLower
        : typeof before?.email === "string"
          ? normalizeEmail(before.email)
          : null;
    const previousPhoneE164 =
      typeof before?.phoneE164 === "string"
        ? before.phoneE164
        : typeof before?.phoneNumber === "string"
          ? normalizePhoneE164(before.phoneNumber)
          : null;

    await syncContactLookupIndexes({
      userId,
      isRegistered,
      contact,
      previousEmailLower,
      previousPhoneE164,
    });
  });
