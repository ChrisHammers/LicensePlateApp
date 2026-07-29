import { describe, it, expect, vi } from "vitest";

vi.mock("./audit", () => ({
  writeAuditLog: vi.fn(),
}));

import {
  DEFAULT_PARTICIPATION_DEFAULTS,
  participationDefaultsFromAppPrefs,
  parseTripParticipantPrefsInput,
  participantPrefsDocFields,
  seedParticipantPrefsIfNeeded,
} from "./tripParticipantPrefs";

describe("participationDefaultsFromAppPrefs", () => {
  it("returns factory defaults when missing", () => {
    expect(participationDefaultsFromAppPrefs(undefined)).toEqual(DEFAULT_PARTICIPATION_DEFAULTS);
    expect(participationDefaultsFromAppPrefs({})).toEqual(DEFAULT_PARTICIPATION_DEFAULTS);
  });

  it("merges partial maps with factory defaults", () => {
    expect(
      participationDefaultsFromAppPrefs({
        participationDefaults: { skipVoiceConfirmation: true },
      })
    ).toEqual({
      ...DEFAULT_PARTICIPATION_DEFAULTS,
      skipVoiceConfirmation: true,
    });
  });
});

describe("parseTripParticipantPrefsInput", () => {
  it("rejects partial maps", () => {
    expect(parseTripParticipantPrefsInput({ skipVoiceConfirmation: true })).toBeNull();
  });

  it("accepts full boolean map", () => {
    expect(
      parseTripParticipantPrefsInput({
        skipVoiceConfirmation: true,
        saveLocationWhenMarkingPlates: false,
        showMyLocationOnLargeMap: true,
        trackMyLocationDuringTrip: false,
      })
    ).toEqual({
      skipVoiceConfirmation: true,
      saveLocationWhenMarkingPlates: false,
      showMyLocationOnLargeMap: true,
      trackMyLocationDuringTrip: false,
    });
  });
});

describe("seedParticipantPrefsIfNeeded", () => {
  it("seeds when doc is missing", async () => {
    const set = vi.fn();
    const batch = { set } as unknown as FirebaseFirestore.WriteBatch;
    const get = vi.fn().mockResolvedValue({ exists: false });
    const prefsRef = { get, path: "prefs/u1" };
    const sessionRef = {
      collection: () => ({ doc: () => prefsRef }),
    } as unknown as FirebaseFirestore.DocumentReference;

    const wrote = await seedParticipantPrefsIfNeeded(
      batch,
      sessionRef,
      "u1",
      { ...DEFAULT_PARTICIPATION_DEFAULTS, skipVoiceConfirmation: true }
    );
    expect(wrote).toBe(true);
    expect(set).toHaveBeenCalledOnce();
    const fields = set.mock.calls[0][1] as Record<string, unknown>;
    expect(fields.source).toBe("seeded_from_account_defaults");
    expect(fields.skipVoiceConfirmation).toBe(true);
    expect(fields.userId).toBe("u1");
  });

  it("does not overwrite user_edit", async () => {
    const set = vi.fn();
    const batch = { set } as unknown as FirebaseFirestore.WriteBatch;
    const get = vi.fn().mockResolvedValue({
      exists: true,
      data: () => ({ source: "user_edit" }),
    });
    const prefsRef = { get };
    const sessionRef = {
      collection: () => ({ doc: () => prefsRef }),
    } as unknown as FirebaseFirestore.DocumentReference;

    const wrote = await seedParticipantPrefsIfNeeded(
      batch,
      sessionRef,
      "u1",
      DEFAULT_PARTICIPATION_DEFAULTS
    );
    expect(wrote).toBe(false);
    expect(set).not.toHaveBeenCalled();
  });

  it("does not overwrite already-seeded docs", async () => {
    const set = vi.fn();
    const batch = { set } as unknown as FirebaseFirestore.WriteBatch;
    const get = vi.fn().mockResolvedValue({
      exists: true,
      data: () => ({ source: "seeded_from_account_defaults" }),
    });
    const prefsRef = { get };
    const sessionRef = {
      collection: () => ({ doc: () => prefsRef }),
    } as unknown as FirebaseFirestore.DocumentReference;

    const wrote = await seedParticipantPrefsIfNeeded(
      batch,
      sessionRef,
      "u1",
      DEFAULT_PARTICIPATION_DEFAULTS
    );
    expect(wrote).toBe(false);
    expect(set).not.toHaveBeenCalled();
  });
});

describe("participantPrefsDocFields", () => {
  it("marks user_edit source for upserts", () => {
    const fields = participantPrefsDocFields("u1", DEFAULT_PARTICIPATION_DEFAULTS, "user_edit");
    expect(fields.source).toBe("user_edit");
    expect(fields.userId).toBe("u1");
  });
});
