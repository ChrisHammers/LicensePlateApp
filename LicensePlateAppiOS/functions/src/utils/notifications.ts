import * as admin from "firebase-admin";
import {
  isSocialPushEnabled,
  notificationPrefsFromUserData,
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
 * Get FCM token for a user
 */
export async function getFCMToken(userId: string): Promise<string | null> {
  const userDoc = await admin.firestore().collection("users").doc(userId).get();
  return userDoc.data()?.fcmToken || null;
}

/**
 * FCM token for friend/family social pushes, gated by `users/{uid}.notificationPrefs`.
 * Missing prefs default to allowed (older clients). Single Firestore read.
 */
export async function getFCMTokenForSocialPush(
  userId: string,
  category: SocialPushCategory
): Promise<string | null> {
  const userDoc = await admin.firestore().collection("users").doc(userId).get();
  const data = userDoc.data();
  if (!data) {
    return null;
  }
  if (!isSocialPushEnabled(notificationPrefsFromUserData(data as Record<string, unknown>), category)) {
    return null;
  }
  return data.fcmToken || null;
}

