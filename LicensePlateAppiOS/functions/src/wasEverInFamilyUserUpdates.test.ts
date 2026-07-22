import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
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
