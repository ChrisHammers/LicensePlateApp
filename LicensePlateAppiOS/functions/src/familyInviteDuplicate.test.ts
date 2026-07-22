import { describe, it, expect } from "vitest";
import {
  shouldRejectDuplicatePendingFamilyInvite,
  PENDING_FAMILY_INVITE_EXISTS_MESSAGE,
} from "./familyInviteDuplicate";

describe("shouldRejectDuplicatePendingFamilyInvite", () => {
  it("rejects when a pending invite already exists", () => {
    expect(shouldRejectDuplicatePendingFamilyInvite(false)).toBe(true);
  });

  it("allows when no pending invite exists", () => {
    expect(shouldRejectDuplicatePendingFamilyInvite(true)).toBe(false);
  });

  it("exports a stable error message for clients", () => {
    expect(PENDING_FAMILY_INVITE_EXISTS_MESSAGE).toBe(
      "Pending invite already exists"
    );
  });
});
