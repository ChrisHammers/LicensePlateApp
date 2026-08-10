import * as admin from "firebase-admin";
import {
  isPushEnabled,
  notificationPrefsFromUserData,
  PushCategory,
  SocialPushCategory,
} from "../notificationPrefs";

/**
 * Send FCM push notification
 */
export async function sendPushNotification(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const message: admin.messaging.Message = {
    token: fcmToken,
    notification: {
      title,
      body,
    },
    data,
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  };

  try {
    await admin.messaging().send(message);
  } catch (error) {
    console.error("Error sending push notification:", error);
    throw error;
  }
}

/**
 * Owner-only push routing doc: `users/{uid}/private/fcm` (FR-43 / audit E1).
 * Firestore reads are document-level, so the token cannot live on the peer-readable
 * `users/{uid}` doc. Clients write it under `private/`; functions read it via Admin SDK.
 */
export const FCM_PRIVATE_DOC_ID = "fcm";

/**
 * Pick the push token from the private doc, falling back to the legacy top-level
 * `users/{uid}.fcmToken` for docs a profile sync / token refresh has not migrated yet.
 */
export function resolveFCMToken(
  privateFcmData: Record<string, unknown> | undefined,
  legacyUserData: Record<string, unknown> | undefined
): string | null {
  const token = privateFcmData?.token;
  if (typeof token === "string" && token.length > 0) {
    return token;
  }
  const legacyToken = legacyUserData?.fcmToken;
  if (typeof legacyToken === "string" && legacyToken.length > 0) {
    return legacyToken;
  }
  return null;
}

function userRef(userId: string): admin.firestore.DocumentReference {
  return admin.firestore().collection("users").doc(userId);
}

async function readUserAndFCMDocs(
  userId: string
): Promise<{
  userData: Record<string, unknown> | undefined;
  fcmData: Record<string, unknown> | undefined;
}> {
  const ref = userRef(userId);
  const [userDoc, fcmDoc] = await Promise.all([
    ref.get(),
    ref.collection("private").doc(FCM_PRIVATE_DOC_ID).get(),
  ]);
  return {
    userData: userDoc.data() as Record<string, unknown> | undefined,
    fcmData: fcmDoc.data() as Record<string, unknown> | undefined,
  };
}

/**
 * Get FCM token for a user (ungated).
 */
export async function getFCMToken(userId: string): Promise<string | null> {
  const { userData, fcmData } = await readUserAndFCMDocs(userId);
  return resolveFCMToken(fcmData, userData);
}

/**
 * FCM token gated by `users/{uid}.notificationPrefs` for any push category.
 * Missing prefs default per `isPushEnabled`. Prefs and token are read in parallel.
 */
export async function getFCMTokenForPush(
  userId: string,
  category: PushCategory
): Promise<string | null> {
  const { userData, fcmData } = await readUserAndFCMDocs(userId);
  if (!userData) {
    return null;
  }
  if (!isPushEnabled(notificationPrefsFromUserData(userData), category)) {
    return null;
  }
  return resolveFCMToken(fcmData, userData);
}

/**
 * @deprecated Use getFCMTokenForPush
 */
export async function getFCMTokenForSocialPush(
  userId: string,
  category: SocialPushCategory
): Promise<string | null> {
  return getFCMTokenForPush(userId, category);
}
