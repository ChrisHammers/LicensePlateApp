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

import { isUserSearchable } from "./utils/validation";

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
});
