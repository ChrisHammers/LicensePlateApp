import * as admin from "firebase-admin";

admin.initializeApp();

// Export all functions
export { createShareCode, redeemShareCode } from "./shareCodes";
export {
  sendFriendInvite,
  respondToFriendInvite,
} from "./friends";
export {
  createFamily,
  sendFamilyInvite,
  respondToFamilyInvite_UserStep,
  approveFamilyJoinRequest_CaptainStep,
  removeFamilyMember,
  changeFamilyMemberRole,
  inactivateFamily,
} from "./family";
export { expireInvitesAndCodes } from "./expiration";
export { onAuthUserDeleted } from "./auth";
export { writeAuditLog } from "./audit";

