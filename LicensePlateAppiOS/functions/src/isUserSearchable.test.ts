import { describe, it, expect, vi, beforeEach } from "vitest";

const getMock = vi.fn();

vi.mock("firebase-admin", () => ({
  default: {
    firestore: () => ({
      collection: () => ({
        doc: () => ({
          get: getMock,
        }),
      }),
    }),
  },
  firestore: () => ({
    collection: () => ({
      doc: () => ({
        get: getMock,
      }),
    }),
  }),
}));

import {
  isContactSearchableFromUserData,
  isUserSearchable,
} from "./utils/validation";

describe("isContactSearchableFromUserData", () => {
  it("returns true when privacy.emailSearchable is true", () => {
    expect(
      isContactSearchableFromUserData(
        { privacy: { emailSearchable: true, phoneSearchable: false } },
        "email"
      )
    ).toBe(true);
  });

  it("returns false when privacy.emailSearchable is false even if legacy public", () => {
    expect(
      isContactSearchableFromUserData(
        { privacy: { emailSearchable: false }, isEmailPublic: true },
        "email"
      )
    ).toBe(false);
  });

  it("defaults to not searchable when flags are missing", () => {
    expect(isContactSearchableFromUserData({}, "email")).toBe(false);
    expect(isContactSearchableFromUserData({}, "phone")).toBe(false);
    expect(isContactSearchableFromUserData(null, "email")).toBe(false);
  });

  it("falls back to legacy isEmailPublic / isPhonePublic", () => {
    expect(
      isContactSearchableFromUserData(
        { isEmailPublic: true, isPhonePublic: false },
        "email"
      )
    ).toBe(true);
    expect(
      isContactSearchableFromUserData(
        { isEmailPublic: true, isPhonePublic: false },
        "phone"
      )
    ).toBe(false);
  });

  it("returns true when privacy.phoneSearchable is true", () => {
    expect(
      isContactSearchableFromUserData(
        { privacy: { phoneSearchable: true } },
        "phone"
      )
    ).toBe(true);
  });

  // FR-10 (COPPA F-5b). This one predicate backs the searchUsers email/phone modalities
  // AND the sendFamilyInvite / sendFriendInvite privacy gates, so the child exclusion
  // lands on all of them at once.
  describe("FR-10: a child is never contact-searchable", () => {
    it("returns false despite every privacy flag being opted in", () => {
      const child = {
        userName: "Kid",
        isRegistered: true,
        isChildAccount: true,
        privacy: { emailSearchable: true, phoneSearchable: true },
        isEmailPublic: true,
        isPhonePublic: true,
      };
      expect(isContactSearchableFromUserData(child, "email")).toBe(false);
      expect(isContactSearchableFromUserData(child, "phone")).toBe(false);
    });

    it("applies to a consented child in a family as well", () => {
      const consentedChild = {
        isChildAccount: true,
        activeFamilyId: "fam1",
        privacy: { emailSearchable: true, phoneSearchable: true },
      };
      expect(isContactSearchableFromUserData(consentedChild, "email")).toBe(false);
      expect(isContactSearchableFromUserData(consentedChild, "phone")).toBe(false);
    });

    it("leaves adults untouched — missing / false flag ⇒ not a child", () => {
      const adult = { privacy: { emailSearchable: true, phoneSearchable: true } };
      expect(isContactSearchableFromUserData(adult, "email")).toBe(true);
      expect(
        isContactSearchableFromUserData({ ...adult, isChildAccount: false }, "email")
      ).toBe(true);
    });
  });

  it("gates email search opt-out used by searchUsers contact modality", () => {
    const optedOut = {
      userName: "Alpha",
      isRegistered: true,
      privacy: { emailSearchable: false, phoneSearchable: false },
    };
    expect(isContactSearchableFromUserData(optedOut, "email")).toBe(false);
    expect(isContactSearchableFromUserData(optedOut, "phone")).toBe(false);

    const optedIn = {
      ...optedOut,
      privacy: { emailSearchable: true, phoneSearchable: true },
    };
    expect(isContactSearchableFromUserData(optedIn, "email")).toBe(true);
    expect(isContactSearchableFromUserData(optedIn, "phone")).toBe(true);
  });
});

describe("isUserSearchable", () => {
  beforeEach(() => {
    getMock.mockReset();
  });

  it("returns true when privacy.emailSearchable is true", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        privacy: { emailSearchable: true, phoneSearchable: false },
      }),
    });

    await expect(isUserSearchable("user-1", "email")).resolves.toBe(true);
  });

  it("returns false when privacy.emailSearchable is false", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        privacy: { emailSearchable: false },
        isEmailPublic: true,
      }),
    });

    await expect(isUserSearchable("user-1", "email")).resolves.toBe(false);
  });

  it("returns false when privacy flags are missing", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({}),
    });

    await expect(isUserSearchable("user-1", "email")).resolves.toBe(false);
    await expect(isUserSearchable("user-1", "phone")).resolves.toBe(false);
  });

  it("falls back to legacy isEmailPublic when privacy map omits emailSearchable", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        isEmailPublic: true,
        isPhonePublic: false,
      }),
    });

    await expect(isUserSearchable("user-1", "email")).resolves.toBe(true);
    await expect(isUserSearchable("user-1", "phone")).resolves.toBe(false);
  });

  it("falls back to legacy isPhonePublic when privacy map omits phoneSearchable", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        privacy: { emailSearchable: false },
        isPhonePublic: true,
      }),
    });

    await expect(isUserSearchable("user-1", "phone")).resolves.toBe(true);
  });

  it("returns true when privacy.phoneSearchable is true", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        privacy: { phoneSearchable: true },
      }),
    });

    await expect(isUserSearchable("user-1", "phone")).resolves.toBe(true);
  });

  it("FR-10: returns false for a child even with both flags opted in", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({
        isChildAccount: true,
        privacy: { emailSearchable: true, phoneSearchable: true },
      }),
    });

    await expect(isUserSearchable("kid", "email")).resolves.toBe(false);
    await expect(isUserSearchable("kid", "phone")).resolves.toBe(false);
  });
});
