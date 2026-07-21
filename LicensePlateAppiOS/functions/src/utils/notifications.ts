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
 * Get FCM token for a user
 */
export async function getFCMToken(userId: string): Promise<string | null> {
  const userDoc = await admin.firestore().collection("users").doc(userId).get();
  return userDoc.data()?.fcmToken || null;
}

/**
 * FCM token gated by `users/{uid}.notificationPrefs` for any push category.
 * Missing prefs default per `isPushEnabled`. Single Firestore read.
 */
export async function getFCMTokenForPush(
  userId: string,
  category: PushCategory
): Promise<string | null> {
  const userDoc = await admin.firestore().collection("users").doc(userId).get();
  const data = userDoc.data();
  if (!data) {
    return null;
  }
  if (!isPushEnabled(notificationPrefsFromUserData(data as Record<string, unknown>), category)) {
    return null;
  }
  return data.fcmToken || null;
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
