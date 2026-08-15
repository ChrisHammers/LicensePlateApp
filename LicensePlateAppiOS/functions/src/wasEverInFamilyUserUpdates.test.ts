import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
  SIGNED_UP_EQUIVALENT_TAG,
  familyMembershipGrantUserUpdate,
  familyMembershipLeaveUserUpdate,
} from "./wasEverInFamilyUserUpdates";

describe("familyMembershipGrantUserUpdate", () => {
  it("sets wasEverInFamily and activeFamilyId for a normal member", () => {
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: false,
      })
    ).toEqual({
      wasEverInFamily: true,
      activeFamilyId: "fam1",
    });
  });

  it("sets wasEverInFamily without activeFamilyId for retired general", () => {
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: true,
      })
    ).toEqual({
      wasEverInFamily: true,
    });
  });
});

describe("familyMembershipLeaveUserUpdate", () => {
  it("sets wasEverInFamily and deletes activeFamilyId for a normal member", () => {
    const update = familyMembershipLeaveUserUpdate({ isRetiredGeneral: false });
    expect(update.wasEverInFamily).toBe(true);
    expect(update.activeFamilyId).toEqual(admin.firestore.FieldValue.delete());
  });

  it("sets wasEverInFamily without clearing activeFamilyId for retired general", () => {
    expect(
      familyMembershipLeaveUserUpdate({ isRetiredGeneral: true })
    ).toEqual({
      wasEverInFamily: true,
    });
  });
});

describe("familyMembershipGrantUserUpdate isChild stamp (COPPA FR-25)", () => {
  it("stamps isChildAccount true on an explicit child grant", () => {
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: false,
        isChild: true,
      })
    ).toEqual({
      wasEverInFamily: true,
      activeFamilyId: "fam1",
      isChildAccount: true,
      // FR-85: the capability grant commits in the same batch as membership.
      entitlementTags: admin.firestore.FieldValue.arrayUnion(SIGNED_UP_EQUIVALENT_TAG),
    });
  });

  it("stamps isChildAccount false on an explicit new-guardian clear", () => {
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: false,
        isChild: false,
      })
    ).toEqual({
      wasEverInFamily: true,
      activeFamilyId: "fam1",
      isChildAccount: false,
    });
  });

  it("leaves the flag untouched when isChild is omitted", () => {
    expect(
      familyMembershipGrantUserUpdate({ familyId: "fam1", isRetiredGeneral: false })
    ).not.toHaveProperty("isChildAccount");
  });
});

/**
 * COPPA FR-85 (F-42) — the consent transaction is where a consented child gains the
 * `.signedUp` capability they lost when FR-60 made them an anonymous account.
 */
describe("familyMembershipGrantUserUpdate FR-85 capability grant", () => {
  it("grants the signed-up-equivalent tag on a child consent capture", () => {
    const update = familyMembershipGrantUserUpdate({
      familyId: "fam1",
      isRetiredGeneral: false,
      isChild: true,
    });
    expect(update.entitlementTags).toEqual(
      admin.firestore.FieldValue.arrayUnion(SIGNED_UP_EQUIVALENT_TAG)
    );
  });

  it("uses arrayUnion, so re-admitting a sticky post-revocation child is idempotent", () => {
    // arrayUnion is a no-op when the tag is already present, which is what makes the
    // re-admission path safe to run repeatedly.
    expect(SIGNED_UP_EQUIVALENT_TAG).toBe("signedUpEquivalent");
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: false,
        isChild: true,
      }).entitlementTags
    ).toEqual(
      familyMembershipGrantUserUpdate({
        familyId: "fam2",
        isRetiredGeneral: false,
        isChild: true,
      }).entitlementTags
    );
  });

  it("grants nothing on an adult grant or a new-guardian child correction", () => {
    expect(
      familyMembershipGrantUserUpdate({ familyId: "fam1", isRetiredGeneral: false })
    ).not.toHaveProperty("entitlementTags");
    expect(
      familyMembershipGrantUserUpdate({
        familyId: "fam1",
        isRetiredGeneral: false,
        isChild: false,
      })
    ).not.toHaveProperty("entitlementTags");
  });

  // FR-85 names this implementation PROHIBITED: `isRegistered` drives
  // `isRegisteredForSearch` / `isSearchIndexEligible`, so writing it here would re-expose
  // the child to user search (the FR-70 failure) and lie in the data model.
  it("never writes isRegistered", () => {
    for (const isChild of [true, false, undefined]) {
      expect(
        familyMembershipGrantUserUpdate({
          familyId: "fam1",
          isRetiredGeneral: false,
          isChild,
        })
      ).not.toHaveProperty("isRegistered");
    }
  });

  it("leaves the tag alone on the leave path (sticky, like wasEverInFamily)", () => {
    expect(
      familyMembershipLeaveUserUpdate({ isRetiredGeneral: false })
    ).not.toHaveProperty("entitlementTags");
  });
});
