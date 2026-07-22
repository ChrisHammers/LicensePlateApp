import * as admin from "firebase-admin";

/**
 * Sticky family-unlock flag on users/{uid}.
 * Grant: set true when membership is established.
 * Leave: set true as a legacy safety net when clearing activeFamilyId.
 */

export function familyMembershipGrantUserUpdate(args: {
  familyId: string;
  isRetiredGeneral: boolean;
}): Record<string, unknown> {
  const update: Record<string, unknown> = {
    wasEverInFamily: true,
  };
  if (!args.isRetiredGeneral) {
    update.activeFamilyId = args.familyId;
  }
  return update;
}

export function familyMembershipLeaveUserUpdate(args: {
  isRetiredGeneral: boolean;
}): Record<string, unknown> {
  const update: Record<string, unknown> = {
    wasEverInFamily: true,
  };
  if (!args.isRetiredGeneral) {
    update.activeFamilyId = admin.firestore.FieldValue.delete();
  }
  return update;
}
