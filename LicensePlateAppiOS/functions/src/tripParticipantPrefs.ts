/**
 * Per-participant trip prefs (voice + location consent).
 * Stored at trip_sessions/{sessionId}/participant_prefs/{userId}.
 * Seeded from users/{uid}.appPrefs.participationDefaults; never on members/{uid}.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "./audit";
import { normalizeClientMetadata } from "./clientMetadata";
import { enforcedCallable } from "./callableOptions";

export type ParticipationDefaults = {
  skipVoiceConfirmation: boolean;
  saveLocationWhenMarkingPlates: boolean;
  showMyLocationOnLargeMap: boolean;
  trackMyLocationDuringTrip: boolean;
};

export const DEFAULT_PARTICIPATION_DEFAULTS: ParticipationDefaults = {
  skipVoiceConfirmation: false,
  saveLocationWhenMarkingPlates: true,
  showMyLocationOnLargeMap: true,
  trackMyLocationDuringTrip: true,
};

export type TripParticipantPrefsSource =
  | "seeded_from_account_defaults"
  | "user_edit";

export function participationDefaultsFromAppPrefs(
  appPrefs: Record<string, unknown> | undefined | null
): ParticipationDefaults {
  const raw = (appPrefs?.participationDefaults as Record<string, unknown> | undefined) ?? undefined;
  const d = DEFAULT_PARTICIPATION_DEFAULTS;
  if (!raw || typeof raw !== "object") {
    return { ...d };
  }
  return {
    skipVoiceConfirmation:
      typeof raw.skipVoiceConfirmation === "boolean"
        ? raw.skipVoiceConfirmation
        : d.skipVoiceConfirmation,
    saveLocationWhenMarkingPlates:
      typeof raw.saveLocationWhenMarkingPlates === "boolean"
        ? raw.saveLocationWhenMarkingPlates
        : d.saveLocationWhenMarkingPlates,
    showMyLocationOnLargeMap:
      typeof raw.showMyLocationOnLargeMap === "boolean"
        ? raw.showMyLocationOnLargeMap
        : d.showMyLocationOnLargeMap,
    trackMyLocationDuringTrip:
      typeof raw.trackMyLocationDuringTrip === "boolean"
        ? raw.trackMyLocationDuringTrip
        : d.trackMyLocationDuringTrip,
  };
}

export function parseTripParticipantPrefsInput(
  raw: Record<string, unknown> | undefined | null
): ParticipationDefaults | null {
  if (!raw || typeof raw !== "object") return null;
  const bool = (key: keyof ParticipationDefaults): boolean | null => {
    const v = raw[key];
    return typeof v === "boolean" ? v : null;
  };
  const skip = bool("skipVoiceConfirmation");
  const save = bool("saveLocationWhenMarkingPlates");
  const show = bool("showMyLocationOnLargeMap");
  const track = bool("trackMyLocationDuringTrip");
  if (skip == null || save == null || show == null || track == null) {
    return null;
  }
  return {
    skipVoiceConfirmation: skip,
    saveLocationWhenMarkingPlates: save,
    showMyLocationOnLargeMap: show,
    trackMyLocationDuringTrip: track,
  };
}

export function participantPrefsDocFields(
  userId: string,
  prefs: ParticipationDefaults,
  source: TripParticipantPrefsSource
): Record<string, unknown> {
  return {
    userId,
    skipVoiceConfirmation: prefs.skipVoiceConfirmation,
    saveLocationWhenMarkingPlates: prefs.saveLocationWhenMarkingPlates,
    showMyLocationOnLargeMap: prefs.showMyLocationOnLargeMap,
    trackMyLocationDuringTrip: prefs.trackMyLocationDuringTrip,
    source,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Seed prefs for a member if missing or still seeded (never overwrite user_edit).
 * Returns true when a write was queued on the batch.
 */
export async function seedParticipantPrefsIfNeeded(
  batch: admin.firestore.WriteBatch,
  sessionRef: admin.firestore.DocumentReference,
  userId: string,
  prefs: ParticipationDefaults
): Promise<boolean> {
  const prefsRef = sessionRef.collection("participant_prefs").doc(userId);
  const snap = await prefsRef.get();
  if (snap.exists) {
    const source = snap.data()?.source as string | undefined;
    if (source === "user_edit") {
      return false;
    }
    // Already seeded: leave alone (idempotent re-join / re-publish).
    return false;
  }
  batch.set(prefsRef, participantPrefsDocFields(userId, prefs, "seeded_from_account_defaults"));
  return true;
}

export async function loadParticipationDefaultsForUser(
  db: admin.firestore.Firestore,
  userId: string
): Promise<ParticipationDefaults> {
  const userSnap = await db.collection("users").doc(userId).get();
  const appPrefs = userSnap.data()?.appPrefs as Record<string, unknown> | undefined;
  return participationDefaultsFromAppPrefs(appPrefs);
}

/**
 * Full-map upsert of the authenticated member's own participant prefs.
 */
export const upsertTripParticipantPrefs = enforcedCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const userId = context.auth.uid;
  const tripSessionId = data?.tripSessionId as string | undefined;
  const prefs = parseTripParticipantPrefsInput(
    data?.prefs as Record<string, unknown> | undefined
  );
  const clientMetadata = normalizeClientMetadata(data?.clientMetadata);

  if (!tripSessionId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "tripSessionId is required"
    );
  }
  if (!prefs) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "prefs must contain all required boolean fields"
    );
  }

  const db = admin.firestore();
  const sessionRef = db.collection("trip_sessions").doc(tripSessionId);
  const memberSnap = await sessionRef.collection("members").doc(userId).get();
  if (!memberSnap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not a member of this trip session"
    );
  }

  await sessionRef
    .collection("participant_prefs")
    .doc(userId)
    .set(participantPrefsDocFields(userId, prefs, "user_edit"));

  await writeAuditLog({
    eventType: "trip_participant_prefs_upserted",
    actorId: userId,
    subjectType: "trip_session",
    subjectId: tripSessionId,
    metadata: { userId },
    clientMetadata,
  });

  return { success: true };
});
