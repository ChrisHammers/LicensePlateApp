import * as admin from "firebase-admin";

/**
 * Sticky family-unlock flag on users/{uid}.
 * Grant: set true when membership is established.
 * Leave: set true as a legacy safety net when clearing activeFamilyId.
 */

export function familyMembershipGrantUserUpdate(args: {
  familyId: string;
  isRetiredGeneral: boolean;
  /**
   * COPPA FR-25 stamp extension: when the approving manager explicitly declares the
   * member's child status, the authoritative `users/{uid}.isChildAccount` flag rides the
   * same membership-grant update (true = consent capture; false = new-guardian
   * correction). Omitted ⇒ the flag is untouched.
   */
  isChild?: boolean;
}): Record<string, unknown> {
  const update: Record<string, unknown> = {
    wasEverInFamily: true,
  };
  if (!args.isRetiredGeneral) {
    update.activeFamilyId = args.familyId;
  }
  if (args.isChild !== undefined) {
    update.isChildAccount = args.isChild;
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
