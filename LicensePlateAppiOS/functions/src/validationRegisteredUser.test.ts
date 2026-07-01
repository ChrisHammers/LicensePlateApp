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
  assertUserIsRegistered,
  recipientNotRegisteredMessage,
} from "./utils/validation";

describe("assertUserIsRegistered", () => {
  beforeEach(() => {
    getMock.mockReset();
  });

  it("allows legacy users without isRegistered field", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({ userName: "legacy-user" }),
    });

    await expect(assertUserIsRegistered("legacy-user")).resolves.toBeUndefined();
  });

  it("allows explicitly registered users", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({ isRegistered: true }),
    });

    await expect(assertUserIsRegistered("signed-user")).resolves.toBeUndefined();
  });

  it("rejects anonymous users marked isRegistered false", async () => {
    getMock.mockResolvedValue({
      exists: true,
      data: () => ({ isRegistered: false }),
    });

    await expect(assertUserIsRegistered("anon-user")).rejects.toThrow(
      recipientNotRegisteredMessage
    );
  });

  it("rejects missing users", async () => {
    getMock.mockResolvedValue({
      exists: false,
      data: () => undefined,
    });

    await expect(assertUserIsRegistered("missing-user")).rejects.toThrow(
      "User not found"
    );
  });
});
