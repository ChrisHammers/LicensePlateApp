import { describe, it, expect } from "vitest";
import { canRemoveFamilyMember } from "./familyMemberRemovalPolicy";

describe("canRemoveFamilyMember", () => {
  it("allows non-creator self-leave", () => {
    for (const role of ["scout", "sergeant", "captain", "retired_general"]) {
      expect(
        canRemoveFamilyMember({ actorRole: role, targetRole: role, isSelf: true })
      ).toEqual({ allowed: true });
    }
  });

  it("rejects creator self-leave", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "creator",
        targetRole: "creator",
        isSelf: true,
      })
    ).toEqual({
      allowed: false,
      code: "failed-precondition",
      message: "Family creators must delete the family instead of leaving",
    });
  });

  it("allows creator to remove anyone else", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "creator",
        targetRole: "scout",
        isSelf: false,
      })
    ).toEqual({ allowed: true });
    expect(
      canRemoveFamilyMember({
        actorRole: "creator",
        targetRole: "captain",
        isSelf: false,
      })
    ).toEqual({ allowed: true });
  });

  it("allows captain to remove non-captain non-creator", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "captain",
        targetRole: "scout",
        isSelf: false,
      })
    ).toEqual({ allowed: true });
  });

  it("rejects captain removing another captain", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "captain",
        targetRole: "captain",
        isSelf: false,
      }).allowed
    ).toBe(false);
  });

  it("allows captain to remove creator (legacy manager rule)", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "captain",
        targetRole: "creator",
        isSelf: false,
      })
    ).toEqual({ allowed: true });
  });

  it("rejects scout removing another member", () => {
    expect(
      canRemoveFamilyMember({
        actorRole: "scout",
        targetRole: "scout",
        isSelf: false,
      })
    ).toEqual({
      allowed: false,
      code: "permission-denied",
      message: "Only Captains can remove members",
    });
  });
});
