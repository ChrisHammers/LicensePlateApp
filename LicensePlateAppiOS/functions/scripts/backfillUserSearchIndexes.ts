/**
 * Backfill search indexes + private/contact for all users.
 *
 * Usage (from functions/):
 *   DRY_RUN=1 npm run backfill:user-search
 *   npm run backfill:user-search
 *   STRIP_PUBLIC_PII=1 npm run backfill:user-search
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or default ADC for the Firebase project.
 * See USER_SEARCH_ROLLBACK.md for rollback.
 */
import * as admin from "firebase-admin";
import {
  buildContactFields,
  isRegisteredForSearch,
  syncContactLookupIndexes,
  syncUsernameSearchIndex,
  PRIVATE_CONTACT_DOC,
} from "../src/userSearchIndex";
import { normalizeUsernameLower } from "../src/userSearchCore";

const DRY_RUN = process.env.DRY_RUN === "1" || process.env.DRY_RUN === "true";
const STRIP_PUBLIC_PII =
  process.env.STRIP_PUBLIC_PII === "1" || process.env.STRIP_PUBLIC_PII === "true";
const BATCH_SIZE = 400;

const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT ||
  "roadtrip-royale-dev-d2652";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

async function processUser(
  userId: string,
  data: FirebaseFirestore.DocumentData
): Promise<{ indexed: boolean; skippedAnon: boolean }> {
  const isRegistered = isRegisteredForSearch(data);
  const userName =
    typeof data.userName === "string"
      ? data.userName
      : typeof data.username === "string"
        ? data.username
        : null;
  const userNameLower = userName ? normalizeUsernameLower(userName) : null;

  // Load Auth email as fallback when Firestore email missing
  let email =
    typeof data.email === "string" && data.email.trim()
      ? data.email
      : null;
  const phoneNumber =
    typeof data.phoneNumber === "string" && data.phoneNumber.trim()
      ? data.phoneNumber
      : null;

  if (!email && isRegistered) {
    try {
      const authUser = await admin.auth().getUser(userId);
      if (authUser.email) email = authUser.email;
    } catch {
      // ignore missing auth user
    }
  }

  const contact = buildContactFields(email, phoneNumber);

  if (DRY_RUN) {
    console.log(
      JSON.stringify({
        userId,
        dryRun: true,
        isRegistered,
        userNameLower,
        hasEmail: !!contact.emailLower,
        hasPhone: !!contact.phoneE164,
        stripPublicPii: STRIP_PUBLIC_PII,
      })
    );
    return { indexed: isRegistered, skippedAnon: !isRegistered };
  }

  if (userNameLower) {
    await db.collection("users").doc(userId).set(
      { userNameLower },
      { merge: true }
    );
  }

  await syncUsernameSearchIndex({
    userId,
    userName,
    previousUserNameLower: typeof data.userNameLower === "string" ? data.userNameLower : null,
    isRegistered,
  });

  const contactRef = db
    .collection("users")
    .doc(userId)
    .collection("private")
    .doc(PRIVATE_CONTACT_DOC);

  await contactRef.set(
    {
      email: contact.email,
      emailLower: contact.emailLower,
      phoneNumber: contact.phoneNumber,
      phoneE164: contact.phoneE164,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await syncContactLookupIndexes({
    userId,
    isRegistered,
    contact,
  });

  if (STRIP_PUBLIC_PII) {
    await db.collection("users").doc(userId).set(
      {
        email: admin.firestore.FieldValue.delete(),
        phoneNumber: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
  }

  return { indexed: isRegistered, skippedAnon: !isRegistered };
}

async function main() {
  console.log(
    `backfillUserSearchIndexes project=${PROJECT_ID} dryRun=${DRY_RUN} stripPublicPii=${STRIP_PUBLIC_PII}`
  );
  if (PROJECT_ID.includes("b694d") || PROJECT_ID.includes("prod")) {
    throw new Error(
      `Refusing to run against apparent production project: ${PROJECT_ID}`
    );
  }

  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let processed = 0;
  let indexed = 0;
  let skippedAnon = 0;

  for (;;) {
    let query = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      try {
        const result = await processUser(doc.id, doc.data());
        processed += 1;
        if (result.skippedAnon) skippedAnon += 1;
        else if (result.indexed) indexed += 1;
      } catch (err) {
        console.error(`Failed ${doc.id}`, err);
      }
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    console.log(`Progress processed=${processed} indexed=${indexed} skippedAnon=${skippedAnon}`);
    if (snap.size < BATCH_SIZE) break;
  }

  console.log(
    `Done processed=${processed} indexed=${indexed} skippedAnon=${skippedAnon}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
