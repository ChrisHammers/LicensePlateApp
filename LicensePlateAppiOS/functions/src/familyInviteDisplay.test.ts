import { describe, it, expect, vi, beforeEach } from "vitest";

const getMock = vi.fn();

vi.mock("firebase-admin", () => ({
  firestore: () => ({
    collection: () => ({
      doc: () => ({
        get: getMock,
      }),
    }),
  }),
}));

describe("loadFamilyName", () => {
  beforeEach(() => {
    getMock.mockReset();
    vi.resetModules();
  });

  it("returns trimmed family name", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({ name: "  Roadtrippers  " }),
    });
    const { loadFamilyName } = await import("./familyInviteDisplay");
    await expect(loadFamilyName("fam-1")).resolves.toBe("Roadtrippers");
  });

  it("returns null when family missing or name empty", async () => {
    getMock.mockResolvedValue({ exists: false, data: () => undefined });
    const { loadFamilyName } = await import("./familyInviteDisplay");
    await expect(loadFamilyName("missing")).resolves.toBeNull();

    getMock.mockResolvedValue({
      exists: true,
      data: () => ({ name: "   " }),
    });
    await expect(loadFamilyName("fam-2")).resolves.toBeNull();
  });
});
