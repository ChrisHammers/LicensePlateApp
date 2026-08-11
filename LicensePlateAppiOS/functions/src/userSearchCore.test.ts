import { describe, it, expect } from "vitest";
import {
  auditQueryFingerprint,
  buildDisplayName,
  classifySearchQuery,
  isRegisteredForSearch,
  isSearchIndexEligible,
  normalizeEmail,
  normalizePhoneE164,
  normalizeUsernameLower,
  phoneLookupDocId,
  toPublicSearchHit,
} from "./userSearchCore";

describe("userSearchCore", () => {
  describe("isRegisteredForSearch", () => {
    it("treats missing isRegistered as registered", () => {
      expect(isRegisteredForSearch({})).toBe(true);
    });
    it("rejects explicit false", () => {
      expect(isRegisteredForSearch({ isRegistered: false })).toBe(false);
    });
    it("accepts explicit true", () => {
      expect(isRegisteredForSearch({ isRegistered: true })).toBe(true);
    });
    it("rejects null data", () => {
      expect(isRegisteredForSearch(null)).toBe(false);
    });
  });

  describe("normalizeEmail", () => {
    it("trims and lowercases", () => {
      expect(normalizeEmail("  John@Gmail.COM ")).toBe("john@gmail.com");
    });
  });

  describe("normalizePhoneE164", () => {
    it("normalizes US formatted numbers", () => {
      expect(normalizePhoneE164("(203) 555-1111")).toBe("+12035551111");
    });
    it("keeps already E.164", () => {
      expect(normalizePhoneE164("+12035551111")).toBe("+12035551111");
    });
    it("returns null for garbage", () => {
      expect(normalizePhoneE164("abc")).toBeNull();
    });
  });

  describe("phoneLookupDocId", () => {
    it("strips plus into p-prefix", () => {
      expect(phoneLookupDocId("+12035551111")).toBe("p12035551111");
    });
  });

  describe("classifySearchQuery", () => {
    it("classifies email", () => {
      expect(classifySearchQuery("john@gmail.com")).toBe("email");
    });
    it("classifies phone", () => {
      expect(classifySearchQuery("(203) 555-1111")).toBe("phone");
    });
    it("classifies username", () => {
      expect(classifySearchQuery("roadtripper")).toBe("username");
    });
    it("falls back to username when digits fail phone parse", () => {
      expect(classifySearchQuery("123")).toBe("username");
    });
  });

  describe("buildDisplayName", () => {
    it("uses first and last", () => {
      expect(
        buildDisplayName({ userName: "u", firstName: "A", lastName: "B" })
      ).toBe("A B");
    });
    it("falls back to userName", () => {
      expect(buildDisplayName({ userName: "solo" })).toBe("solo");
    });
  });

  describe("toPublicSearchHit", () => {
    it("returns public fields only and omits anonymous", () => {
      expect(
        toPublicSearchHit(
          "u1",
          {
            userName: "Alpha",
            firstName: "Al",
            email: "secret@x.com",
            phoneNumber: "2035551111",
            isRegistered: false,
          },
          "email"
        )
      ).toBeNull();
    });

    it("builds hit without email/phone keys", () => {
      const hit = toPublicSearchHit(
        "u1",
        {
          userName: "Alpha",
          firstName: "Al",
          lastName: "Ph",
          avatarId: "avatar_1",
          email: "secret@x.com",
          isRegistered: true,
        },
        "email"
      );
      expect(hit).toEqual({
        userId: "u1",
        userName: "Alpha",
        displayName: "Al Ph",
        avatarId: "avatar_1",
        matchedField: "email",
      });
      expect(hit && "email" in hit).toBe(false);
    });

    it("treats missing isRegistered as discoverable", () => {
      const hit = toPublicSearchHit(
        "legacy",
        { userName: "Legacy" },
        "username"
      );
      expect(hit?.userId).toBe("legacy");
    });

    // FR-9 (COPPA F-5b) — the single choke point every searchUsers modality funnels
    // through, including the raw userNameLower prefix scan.
    describe("FR-9: children never surface in a search result", () => {
      const child = {
        userName: "KidRacer",
        firstName: "Kid",
        lastName: "Racer",
        avatarId: "avatar_2",
        isRegistered: true,
        isChildAccount: true,
      };

      it("returns null for a child on every modality", () => {
        for (const field of ["username", "email", "phone"] as const) {
          expect(toPublicSearchHit("kid", child, field)).toBeNull();
        }
      });

      it("returns null for a consented child in a family too (no carve-out here)", () => {
        expect(
          toPublicSearchHit(
            "kid",
            { ...child, activeFamilyId: "fam1" },
            "username"
          )
        ).toBeNull();
      });

      it("pins missing flag ⇒ adult, and explicit false ⇒ adult", () => {
        expect(
          toPublicSearchHit("adult", { userName: "Grown" }, "username")?.userId
        ).toBe("adult");
        expect(
          toPublicSearchHit(
            "adult",
            { userName: "Grown", isChildAccount: false },
            "username"
          )?.userId
        ).toBe("adult");
      });

      it("ignores non-boolean truthy values (only literal true is a child)", () => {
        expect(
          toPublicSearchHit(
            "odd",
            { userName: "Odd", isChildAccount: "true" },
            "username"
          )?.userId
        ).toBe("odd");
      });
    });
  });

  // FR-11 (COPPA F-5b): the syncers' eligibility predicate.
  describe("isSearchIndexEligible", () => {
    it("treats a child exactly like a non-registered account", () => {
      expect(isSearchIndexEligible({ isChildAccount: true })).toBe(false);
      expect(
        isSearchIndexEligible({ isRegistered: true, isChildAccount: true })
      ).toBe(false);
      expect(
        isSearchIndexEligible({
          isRegistered: true,
          isChildAccount: true,
          activeFamilyId: "fam1",
        })
      ).toBe(false);
      expect(isSearchIndexEligible({ isRegistered: false })).toBe(false);
      expect(isSearchIndexEligible(null)).toBe(false);
    });

    it("keeps adults eligible, including legacy docs with no flags at all", () => {
      expect(isSearchIndexEligible({})).toBe(true);
      expect(isSearchIndexEligible({ isRegistered: true })).toBe(true);
      expect(isSearchIndexEligible({ isChildAccount: false })).toBe(true);
    });
  });

  describe("auditQueryFingerprint", () => {
    it("fully hashes every modality (see auditRedaction.test.ts for the leak checks)", () => {
      expect(auditQueryFingerprint("email", "john@gmail.com")).toMatch(
        /^email:[0-9a-f]{16}$/
      );
      expect(auditQueryFingerprint("phone", "(203) 555-1111")).toMatch(
        /^phone:[0-9a-f]{16}$/
      );
      expect(auditQueryFingerprint("username", "roadtrip")).toMatch(
        /^username:[0-9a-f]{16}$/
      );
    });
  });

  describe("normalizeUsernameLower", () => {
    it("lowercases", () => {
      expect(normalizeUsernameLower(" RoadTrip ")).toBe("roadtrip");
    });
  });
});
