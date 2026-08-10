/**
 * One-time cleanup: delete every `users/{uid}/private/lastLoginLocationData` doc.
 *
 * The silent login-location capture flow was removed (COPPA remediation FR-42 / audit D1).
 * This purges the coordinates it already wrote. Dev data only — the app is unshipped.
 *
 * Run manually (from functions/). This is NOT a deployed function.
 *   DRY_RUN=1 npm run cleanup:login-location
 *   npm run cleanup:login-location
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or default ADC for the Firebase project.
 * The Admin SDK bypasses security rules, so it still works after the client write
 * allowance for this doc was removed from firestore.rules.
 */
import * as admin from "firebase-admin";

const DRY_RUN = process.env.DRY_RUN === "1" || process.env.DRY_RUN === "true";
const BATCH_SIZE = 400;
const PRIVATE_LOGIN_LOCATION_DOC = "lastLoginLocationData";

const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT ||
  "roadtrip-royale-dev-d2652";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

async function main() {
  console.log(
    `deleteLoginLocationData project=${PROJECT_ID} dryRun=${DRY_RUN}`
  );
  if (PROJECT_ID.includes("b694d") || PROJECT_ID.includes("prod")) {
    throw new Error(
      `Refusing to run against apparent production project: ${PROJECT_ID}`
    );
  }

  // listDocuments() also returns refs for user ids that exist only as subcollection
  // parents, so orphaned location docs are still found.
  const userRefs = await db.collection("users").listDocuments();
  console.log(`Scanning ${userRefs.length} user document refs`);

  let scanned = 0;
  let found = 0;
  let deleted = 0;

  for (const refs of chunk(userRefs, BATCH_SIZE)) {
    const locationRefs = refs.map((userRef) =>
      userRef.collection("private").doc(PRIVATE_LOGIN_LOCATION_DOC)
    );
    const snaps = await db.getAll(...locationRefs);
    const existing = snaps.filter((snap) => snap.exists);

    scanned += refs.length;
    found += existing.length;

    if (existing.length > 0 && !DRY_RUN) {
      const batch = db.batch();
      for (const snap of existing) {
        batch.delete(snap.ref);
      }
      await batch.commit();
      deleted += existing.length;
    }

    for (const snap of existing) {
      console.log(
        JSON.stringify({
          userId: snap.ref.parent.parent?.id ?? null,
          dryRun: DRY_RUN,
          deleted: !DRY_RUN,
        })
      );
    }

    console.log(`Progress scanned=${scanned} found=${found} deleted=${deleted}`);
  }

  console.log(`Done scanned=${scanned} found=${found} deleted=${deleted}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
