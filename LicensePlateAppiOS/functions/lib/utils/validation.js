"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getFamilyRoleCounts = getFamilyRoleCounts;
exports.canAddMemberToFamily = canAddMemberToFamily;
exports.checkFriendCap = checkFriendCap;
exports.isUserSearchable = isUserSearchable;
const admin = require("firebase-admin");
const db = admin.firestore();
/**
 * Get role counts for a family
 */
async function getFamilyRoleCounts(familyId) {
    const membersRef = db.collection(`families/${familyId}/members`);
    const snapshot = await membersRef.get();
    let captains = 0;
    let scoutsSergeants = 0;
    let retiredGenerals = 0;
    snapshot.forEach((doc) => {
        const role = doc.data().role;
        if (role === "captain") {
            captains++;
        }
        else if (role === "scout" || role === "sergeant") {
            scoutsSergeants++;
        }
        else if (role === "retired_general") {
            retiredGenerals++;
        }
    });
    return { captains, scoutsSergeants, retiredGenerals };
}
/**
 * Check if user can be added to family based on role limits
 */
async function canAddMemberToFamily(familyId, newRole, userId) {
    const counts = await getFamilyRoleCounts(familyId);
    // Check role-specific limits
    if (newRole === "captain" && counts.captains >= 2) {
        return { canAdd: false, reason: "Maximum 2 captains allowed" };
    }
    if ((newRole === "scout" || newRole === "sergeant") &&
        counts.scoutsSergeants >= 4) {
        return { canAdd: false, reason: "Maximum 4 scouts/sergeants combined" };
    }
    if (newRole === "retired_general" && counts.retiredGenerals >= 4) {
        return { canAdd: false, reason: "Maximum 4 retired generals allowed" };
    }
    // Check if user is already in an active family (unless retired general)
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    if (!(userData === null || userData === void 0 ? void 0 : userData.isRetiredGeneral)) {
        if ((userData === null || userData === void 0 ? void 0 : userData.activeFamilyId) && userData.activeFamilyId !== familyId) {
            return {
                canAdd: false,
                reason: "User is already in another active family",
            };
        }
    }
    return { canAdd: true };
}
/**
 * Check if user has reached friend cap (100)
 */
async function checkFriendCap(userId) {
    var _a;
    const userDoc = await db.collection("users").doc(userId).get();
    const friendCount = ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.friendCount) || 0;
    return {
        canAdd: friendCount < 100,
        currentCount: friendCount,
    };
}
/**
 * Check if user is searchable by email/phone
 */
async function isUserSearchable(userId, searchType) {
    var _a;
    const userDoc = await db.collection("users").doc(userId).get();
    const privacy = ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.privacy) || {};
    if (searchType === "email") {
        return privacy.emailSearchable === true;
    }
    else {
        return privacy.phoneSearchable === true;
    }
}
//# sourceMappingURL=validation.js.map