import * as admin from "firebase-admin";

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

