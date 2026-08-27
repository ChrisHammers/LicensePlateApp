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
export { upsertTripParticipantPrefs } from "./tripParticipantPrefs";
export {
  createFamily,
  sendFamilyInvite,
  respondToFamilyInvite_UserStep,
  approveFamilyJoinRequest_CaptainStep,
  removeFamilyMember,
  changeFamilyMemberRole,
  inactivateFamily,
} from "./family";
export {
  setFamilyMemberChildStatus,
  declareChildRegistration,
  requestChildDataDeletion,
  getParentalConsentStatus,
} from "./familyChildStatus";
export { expireInvitesAndCodes } from "./expiration";
export {
  purgeExpiredInvitesAndCodes,
  purgeExpiredAuditLogs,
  purgeExpiredProvisionalChildAccounts,
  expireLapsedConsentRequests,
  reconcileParentalConsentRecords,
} from "./retention";
export { onAuthUserDeleted } from "./auth";
export { deleteAccount } from "./accountDeletion";
export { onTripEndedUpdatePublicLifetimeStats } from "./publicLifetimeStatsOnTripEnded";
// FR-28h: finds accepted after the trip-end stats one-shot already ran.
export { onLateReplayUpdatePublicLifetimeStats } from "./publicLifetimeStatsOnLateReplay";
export { onTripEndedNotifyMembers } from "./tripEndedNotifyMembers";
export { onRegionFoundNotifyMembers, flushPlateFoundNotifyBuffers } from "./plateFoundNotifyMembers";
export { onActivityEventUpdateUserProgression } from "./progressionOnActivityEvent";
export { ensureUserProgressionDocument } from "./progressionBootstrap";
export { ensureFounderEntitlementIfEligible } from "./founderEntitlement";
export { syncUserAchievementUnlocks } from "./syncUserAchievementUnlocks";
export { claimReturnStreakDailyXp } from "./claimReturnStreakDailyXp";
export { reconcileXpGrantLedger } from "./reconcileXpGrantLedger";

export {
  searchUsers,
  onUserProfileSearchIndexSync,
  onUserContactSearchIndexSync,
} from "./userSearch";
export { onUserProfileSendWelcomeEmail } from "./welcomeEmail";

// FR-59/FR-59.1 email_plus consent core (SRS v3 §3.1.2)
export {
  onConsentRequestCreatedSendEmail,
  confirmParentalConsent,
  deliverConsentPlusNotices,
} from "./consentRequests";

