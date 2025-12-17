"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.writeAuditLog = exports.onAuthUserDeleted = exports.expireInvitesAndCodes = exports.changeFamilyMemberRole = exports.removeFamilyMember = exports.approveFamilyJoinRequest_CaptainStep = exports.respondToFamilyInvite_UserStep = exports.sendFamilyInvite = exports.createFamily = exports.respondToFriendInvite = exports.sendFriendInvite = exports.redeemShareCode = exports.createShareCode = void 0;
const admin = require("firebase-admin");
admin.initializeApp();
// Export all functions
var shareCodes_1 = require("./shareCodes");
Object.defineProperty(exports, "createShareCode", { enumerable: true, get: function () { return shareCodes_1.createShareCode; } });
Object.defineProperty(exports, "redeemShareCode", { enumerable: true, get: function () { return shareCodes_1.redeemShareCode; } });
var friends_1 = require("./friends");
Object.defineProperty(exports, "sendFriendInvite", { enumerable: true, get: function () { return friends_1.sendFriendInvite; } });
Object.defineProperty(exports, "respondToFriendInvite", { enumerable: true, get: function () { return friends_1.respondToFriendInvite; } });
var family_1 = require("./family");
Object.defineProperty(exports, "createFamily", { enumerable: true, get: function () { return family_1.createFamily; } });
Object.defineProperty(exports, "sendFamilyInvite", { enumerable: true, get: function () { return family_1.sendFamilyInvite; } });
Object.defineProperty(exports, "respondToFamilyInvite_UserStep", { enumerable: true, get: function () { return family_1.respondToFamilyInvite_UserStep; } });
Object.defineProperty(exports, "approveFamilyJoinRequest_CaptainStep", { enumerable: true, get: function () { return family_1.approveFamilyJoinRequest_CaptainStep; } });
Object.defineProperty(exports, "removeFamilyMember", { enumerable: true, get: function () { return family_1.removeFamilyMember; } });
Object.defineProperty(exports, "changeFamilyMemberRole", { enumerable: true, get: function () { return family_1.changeFamilyMemberRole; } });
var expiration_1 = require("./expiration");
Object.defineProperty(exports, "expireInvitesAndCodes", { enumerable: true, get: function () { return expiration_1.expireInvitesAndCodes; } });
var auth_1 = require("./auth");
Object.defineProperty(exports, "onAuthUserDeleted", { enumerable: true, get: function () { return auth_1.onAuthUserDeleted; } });
var audit_1 = require("./audit");
Object.defineProperty(exports, "writeAuditLog", { enumerable: true, get: function () { return audit_1.writeAuditLog; } });
//# sourceMappingURL=index.js.map