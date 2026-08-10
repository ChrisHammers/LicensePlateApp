import { describe, it, expect } from "vitest";
import {
  DELETED_USER_TOMBSTONE_PREFIX,
  deletedUserTombstoneIdFor,
  deidentifyEventFields,
  deidentifySessionFields,
} from "./accountDeletionDeidentifyCore";

const UID = "uid_deleted_0000000000000000";
const OTHER = "uid_other_00000000000000000";
// Per-user tombstone for the uid under test; existing assertions keep the old name.
const DELETED_USER_TOMBSTONE = deletedUserTombstoneIdFor(UID);

describe("deidentifyEventFields", () => {
  it("returns null for events that do not name the user (keeps a re-run a no-op)", () => {
    expect(
      deidentifyEventFields(
        { actorId: OTHER, payload: { participantId: OTHER, locationLatitude: "41.7" } },
        UID
      )
    ).toBeNull();
    expect(deidentifyEventFields(null, UID)).toBeNull();
    expect(deidentifyEventFields({ actorId: DELETED_USER_TOMBSTONE, payload: {} }, UID)).toBeNull();
  });

  it("tombstones the actor and strips every location key", () => {
    const result = deidentifyEventFields(
      {
        actorId: UID,
        payload: {
          regionId: "CA",
          participantId: UID,
          locationLatitude: "41.7",
          locationLongitude: "-72.6",
          locationAltitude: "18",
          locationHorizontalAccuracy: "5",
          locationVerticalAccuracy: "3",
          locationTimestamp: "1700000000",
        },
      },
      UID
    );
    expect(result).toEqual({
      actorId: DELETED_USER_TOMBSTONE,
      payload: { regionId: "CA", participantId: DELETED_USER_TOMBSTONE },
    });
  });

  it("rewrites only uid-valued keys, leaving other uids and values alone", () => {
    expect(
      deidentifyEventFields(
        {
          actorId: OTHER,
          payload: {
            participantId: OTHER,
            firstFinderParticipantId: UID,
            initiatedByUserId: OTHER,
            leaveReason: "kicked",
            regionId: "CA",
          },
        },
        UID
      )
    ).toEqual({
      actorId: OTHER,
      payload: {
        participantId: OTHER,
        firstFinderParticipantId: DELETED_USER_TOMBSTONE,
        initiatedByUserId: OTHER,
        leaveReason: "kicked",
        regionId: "CA",
      },
    });
  });

  it("does not rewrite a non-uid field that happens to hold the uid string", () => {
    const result = deidentifyEventFields(
      { actorId: UID, payload: { rejectionReason: UID } },
      UID
    );
    expect(result?.payload.rejectionReason).toBe(UID);
  });

  it("tombstones a missing actorId when the payload names the user", () => {
    expect(deidentifyEventFields({ payload: { participantId: UID } }, UID)).toEqual({
      actorId: DELETED_USER_TOMBSTONE,
      payload: { participantId: DELETED_USER_TOMBSTONE },
    });
  });
});

describe("deidentifySessionFields", () => {
  it("returns null when the session doc is already clean", () => {
    expect(
      deidentifySessionFields(
        { createdBy: OTHER, canonicalParticipants: [{ userId: OTHER }] },
        UID
      )
    ).toBeNull();
  });

  it("tombstones createdBy / canonicalEndedBy and the roster row (never prunes)", () => {
    expect(
      deidentifySessionFields(
        {
          name: "Trip",
          createdBy: UID,
          canonicalEndedBy: UID,
          canonicalParticipants: [{ userId: UID }, { userId: OTHER }],
        },
        UID
      )
    ).toEqual({
      createdBy: DELETED_USER_TOMBSTONE,
      canonicalEndedBy: DELETED_USER_TOMBSTONE,
      // The row survives with the tombstone id: their de-identified events stay
      // on the trip, so the participant count must not silently drop.
      canonicalParticipants: [{ userId: DELETED_USER_TOMBSTONE }, { userId: OTHER }],
    });
  });

  it("touches only the fields that actually name the user", () => {
    expect(
      deidentifySessionFields({ createdBy: OTHER, canonicalEndedBy: UID }, UID)
    ).toEqual({ canonicalEndedBy: DELETED_USER_TOMBSTONE });
  });
});

describe("deletedUserTombstoneIdFor", () => {
  it("is stable, prefix-tagged, distinct per user, and carries no uid material", () => {
    const a = deletedUserTombstoneIdFor(UID);
    expect(a).toBe(deletedUserTombstoneIdFor(UID)); // deterministic — re-runs stay idempotent
    expect(a.startsWith(`${DELETED_USER_TOMBSTONE_PREFIX}-`)).toBe(true);
    expect(a).not.toBe(deletedUserTombstoneIdFor(OTHER)); // leaderboards never merge deleted users
    expect(a).not.toContain(UID); // no PII / uid substring survives
  });
});
