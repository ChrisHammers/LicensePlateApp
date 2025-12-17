"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendPushNotification = sendPushNotification;
exports.getFCMToken = getFCMToken;
const admin = require("firebase-admin");
/**
 * Send FCM push notification
 */
async function sendPushNotification(fcmToken, title, body, data) {
    const message = {
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
    }
    catch (error) {
        console.error("Error sending push notification:", error);
        throw error;
    }
}
/**
 * Get FCM token for a user
 */
async function getFCMToken(userId) {
    var _a;
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    return ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken) || null;
}
//# sourceMappingURL=notifications.js.map