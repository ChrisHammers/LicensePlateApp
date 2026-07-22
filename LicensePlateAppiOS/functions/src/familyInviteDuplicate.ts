/**
 * Pure helper for sendFamilyInvite duplicate-pending guard.
 * Keyed by family + invitee (any sender), not sender identity.
 */
export function shouldRejectDuplicatePendingFamilyInvite(
  existingPendingEmpty: boolean
): boolean {
  return !existingPendingEmpty;
}

export const PENDING_FAMILY_INVITE_EXISTS_MESSAGE =
  "Pending invite already exists";
