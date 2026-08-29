import * as admin from "firebase-admin";
import {
  normalizeEmail,
  normalizePhoneE164,
  normalizeUsernameLower,
  phoneLookupDocId,
  isRegisteredForSearch,
} from "./userSearchCore";

function db() {
  return admin.firestore();
}

export const COLLECTION_LOOKUP_EMAIL = "user_lookup_email";
export const COLLECTION_LOOKUP_PHONE = "user_lookup_phone";
export const COLLECTION_USERNAMES = "usernames";
export const PRIVATE_CONTACT_DOC = "contact";

export interface ContactFields {
  email: string | null;
  emailLower: string | null;
  phoneNumber: string | null;
  phoneE164: string | null;
}

export function buildContactFields(
  email: string | null | undefined,
  phoneNumber: string | null | undefined
): ContactFields {
  const emailRaw = email?.trim() || null;
  const phoneRaw = phoneNumber?.trim() || null;
  return {
    email: emailRaw,
    emailLower: emailRaw ? normalizeEmail(emailRaw) : null,
    phoneNumber: phoneRaw,
    phoneE164: phoneRaw ? normalizePhoneE164(phoneRaw) : null,
  };
}

/**
 * Firestore `update()` on a missing document: the admin SDK throws gRPC code 5
 * ("No document to update"); the test fake throws "update() on missing document".
 * Both mean the same thing to a stamper: the account is mid-deletion or gone, and
 * the correct outcome is no write at all.
 */
function isMissingDocumentUpdateError(error: unknown): boolean {
  const code = (error as { code?: unknown })?.code;
  if (code === 5 || code === "not-found" || code === "NOT_FOUND") return true;
  const message = error instanceof Error ? error.message : String(error);
  return /no document to update|missing document/i.test(message);
}

/**
 * Sync username index + userNameLower for a user doc.
 * Deletes username / contact lookup indexes when not registered.
 */
export async function syncUsernameSearchIndex(params: {
  userId: string;
  userName: string | null | undefined;
  previousUserNameLower?: string | null;
  isRegistered: boolean;
}): Promise<void> {
  const { userId, isRegistered } = params;
  const userNameLower = params.userName
    ? normalizeUsernameLower(params.userName)
    : null;
  const previous = params.previousUserNameLower
    ? normalizeUsernameLower(params.previousUserNameLower)
    : null;

  const writes: Array<() => void> = [];
  const firestore = db();
  const batch = firestore.batch();
  const userRef = firestore.collection("users").doc(userId);

  // §3.1.1 item 9 + FR-11: the `userNameLower` stamp exists only so REGISTERED
  // accounts are findable by the fallback/prefix scans — children and anonymous
  // accounts are never searchable, so they never get the stamp. And it must be an
  // update(), never set(merge): the old create-if-missing stamp let a stale trigger
  // execution RECREATE a deleted child's `users/{uid}` as `{userNameLower}` after
  // account deletion (observed live 2026-08-29). A missing doc stays missing.
  const stampUserNameLower = async () => {
    if (!isRegistered || !userNameLower) return;
    try {
      await userRef.update({ userNameLower });
    } catch (error) {
      if (isMissingDocumentUpdateError(error)) return;
      throw error;
    }
  };

  if (!isRegistered) {
    if (previous) {
      writes.push(() =>
        batch.delete(firestore.collection(COLLECTION_USERNAMES).doc(previous))
      );
    }
    if (userNameLower && userNameLower !== previous) {
      writes.push(() =>
        batch.delete(firestore.collection(COLLECTION_USERNAMES).doc(userNameLower))
      );
    }
    if (writes.length === 0) return;
    writes.forEach((w) => w());
    await batch.commit();
    return;
  }

  if (previous && previous !== userNameLower) {
    const prevRef = firestore.collection(COLLECTION_USERNAMES).doc(previous);
    const prevSnap = await prevRef.get();
    if (prevSnap.exists && prevSnap.data()?.userId === userId) {
      writes.push(() => batch.delete(prevRef));
    }
  }

  if (userNameLower) {
    const unameRef = firestore.collection(COLLECTION_USERNAMES).doc(userNameLower);
    const existing = await unameRef.get();
    if (existing.exists && existing.data()?.userId !== userId) {
      console.warn(
        `usernames/${userNameLower} already owned by ${existing.data()?.userId}; skip for ${userId}`
      );
    } else {
      writes.push(() =>
        batch.set(unameRef, {
          userId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        })
      );
    }
  }

  if (writes.length > 0) {
    writes.forEach((w) => w());
    await batch.commit();
  }
  await stampUserNameLower();
}

/**
 * Upsert or delete email/phone lookup docs for a registered user.
 * When not registered, deletes lookups for the provided keys (and optional previous keys).
 */
export async function syncContactLookupIndexes(params: {
  userId: string;
  isRegistered: boolean;
  contact: ContactFields;
  previousEmailLower?: string | null;
  previousPhoneE164?: string | null;
}): Promise<void> {
  const {
    userId,
    isRegistered,
    contact,
    previousEmailLower,
    previousPhoneE164,
  } = params;

  const firestore = db();
  const batch = firestore.batch();
  let opCount = 0;

  const deleteEmailKey = async (key: string | null | undefined) => {
    if (!key) return;
    const ref = firestore.collection(COLLECTION_LOOKUP_EMAIL).doc(key);
    const snap = await ref.get();
    if (snap.exists && snap.data()?.userId === userId) {
      batch.delete(ref);
      opCount += 1;
    }
  };

  const deletePhoneKey = async (e164: string | null | undefined) => {
    if (!e164) return;
    const ref = firestore.collection(COLLECTION_LOOKUP_PHONE).doc(phoneLookupDocId(e164));
    const snap = await ref.get();
    if (snap.exists && snap.data()?.userId === userId) {
      batch.delete(ref);
      opCount += 1;
    }
  };

  if (!isRegistered) {
    await deleteEmailKey(contact.emailLower);
    await deleteEmailKey(previousEmailLower);
    await deletePhoneKey(contact.phoneE164);
    await deletePhoneKey(previousPhoneE164);
    if (opCount > 0) await batch.commit();
    return;
  }

  if (previousEmailLower && previousEmailLower !== contact.emailLower) {
    await deleteEmailKey(previousEmailLower);
  }

  if (previousPhoneE164 && previousPhoneE164 !== contact.phoneE164) {
    await deletePhoneKey(previousPhoneE164);
  }

  if (contact.emailLower) {
    const ref = firestore.collection(COLLECTION_LOOKUP_EMAIL).doc(contact.emailLower);
    const existing = await ref.get();
    if (existing.exists && existing.data()?.userId !== userId) {
      console.warn(
        `user_lookup_email/${contact.emailLower} owned by ${existing.data()?.userId}; skip ${userId}`
      );
    } else {
      batch.set(ref, {
        userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      opCount += 1;
    }
  } else if (previousEmailLower) {
    await deleteEmailKey(previousEmailLower);
  }

  if (contact.phoneE164) {
    const ref = firestore
      .collection(COLLECTION_LOOKUP_PHONE)
      .doc(phoneLookupDocId(contact.phoneE164));
    const existing = await ref.get();
    if (existing.exists && existing.data()?.userId !== userId) {
      console.warn(
        `user_lookup_phone owned by ${existing.data()?.userId}; skip ${userId}`
      );
    } else {
      batch.set(ref, {
        userId,
        phoneE164: contact.phoneE164,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      opCount += 1;
    }
  } else if (previousPhoneE164) {
    await deletePhoneKey(previousPhoneE164);
  }

  if (opCount > 0) await batch.commit();
}

export async function clearAllSearchIndexesForUser(userId: string, hints: {
  userNameLower?: string | null;
  emailLower?: string | null;
  phoneE164?: string | null;
}): Promise<void> {
  await syncUsernameSearchIndex({
    userId,
    userName: hints.userNameLower,
    previousUserNameLower: hints.userNameLower,
    isRegistered: false,
  });
  await syncContactLookupIndexes({
    userId,
    isRegistered: false,
    contact: {
      email: null,
      emailLower: hints.emailLower ?? null,
      phoneNumber: null,
      phoneE164: hints.phoneE164 ?? null,
    },
    previousEmailLower: hints.emailLower,
    previousPhoneE164: hints.phoneE164,
  });
}

export { isRegisteredForSearch };
