import * as admin from "firebase-admin";

/**
 * Sticky family-unlock flag on users/{uid}.
 * Grant: set true when membership is established.
 * Leave: set true as a legacy safety net when clearing activeFamilyId.
 */

/**
 * COPPA FR-85 (F-42) — the entitlement half of "a consented child is a full member".
 *
 * FR-60 made consented children ANONYMOUS Firebase accounts, and the client resolves the
 * `.signedUp` tier from the auth provider (`AccountState.isGuestLike`). A consented child
 * therefore fell to `.guest` and silently lost the six `.signedUp` avatars they are
 * entitled to. This tag is the grant: it rides the consent transaction, lands in the
 * server-controlled `users/{uid}.entitlementTags` array (FR-7 diff-guard: a client may
 * carry it through a merge but can never add, change or remove it), and the client's
 * `EntitlementState.effectiveTier` floors at `.signedUp` when it is present.
 *
 * Deliberately NOT `isRegistered: true` (FR-85 names that implementation prohibited):
 * that field drives `isRegisteredForSearch` / `isSearchIndexEligible`, so writing it would
 * both lie in the data model and risk re-indexing the child into user search — the FR-70
 * failure. This tag is inert to every search and discoverability predicate.
 *
 * Sticky by design, exactly like `wasEverInFamily` alongside it: a child who leaves or has
 * consent revoked keeps the cosmetic tier the same way they keep the `.family` avatars.
 * Nothing gated on `.signedUp` is a data-collection or spend surface (ad eligibility is
 * `< .gold`, the active-trip limit is 1 for both `.guest` and `.signedUp`, and the
 * saved-trip cap reads `AccountState.isGuestLike` directly, not the tier).
 */
export const SIGNED_UP_EQUIVALENT_TAG = "signedUpEquivalent";

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
  // FR-85: `isChild === true` here IS the consent capture (FR-31 acknowledgments were
  // required to reach it), so the capability grant commits in the same batch as membership
  // — there is no window where a child is consented but second-class. arrayUnion keeps
  // re-admission of a sticky post-revocation child idempotent.
  if (args.isChild === true) {
    update.entitlementTags = admin.firestore.FieldValue.arrayUnion(
      SIGNED_UP_EQUIVALENT_TAG
    );
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
