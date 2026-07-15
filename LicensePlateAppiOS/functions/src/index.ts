import * as admin from "firebase-admin";

admin.initializeApp();
admin.firestore().settings({ ignoreUndefinedProperties: true });

// Export all functions
export { createShareCode, redeemShareCode } from "./shareCodes";
export {
  sendFriendInvite,
  respondToFriendInvite,
  removeFriend,
} from "./friends";
export {
  sendTripInvite,
  respondToTripInvite,
  cancelTripInvite,
} from "./tripInvites";
export {
  publishTripCanonicalState,
  appendTripActivityEvent,
  fetchTripBootstrapForMember,
  markTripCancelledRemote,
  updateFairnessAckWatermark,
  removeTripParticipantAsOwner,
} from "./tripSessionCanonical";
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
export { onTripEndedUpdatePublicLifetimeStats } from "./publicLifetimeStatsOnTripEnded";
export { onTripEndedNotifyMembers } from "./tripEndedNotifyMembers";
export { onActivityEventUpdateUserProgression } from "./progressionOnActivityEvent";
export { ensureUserProgressionDocument } from "./progressionBootstrap";
export { ensureFounderEntitlementIfEligible } from "./founderEntitlement";
export { syncUserAchievementUnlocks } from "./syncUserAchievementUnlocks";
export { reconcileXpGrantLedger } from "./reconcileXpGrantLedger";
export {
  searchUsers,
  onUserProfileSearchIndexSync,
  onUserContactSearchIndexSync,
} from "./userSearch";

