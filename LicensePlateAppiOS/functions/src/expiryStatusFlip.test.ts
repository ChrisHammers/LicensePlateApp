/**
 * FR-77 closes audit L-7 — the `expireInvitesAndCodes` status-flip pass is bounded.
 *
 * The pass this covers used to read its whole match set with one unbounded `.get()` and stage
 * every result into a single `WriteBatch`. A Firestore batch is capped at 500 operations, so
 * the 501st expired row would have thrown and left the entire pass — every collection in it —
 * permanently wedged. The over-500 case below is the regression pin for exactly that: it fails
 * against the old shape (FakeFirestore's WriteBatch enforces the same 500-op cap) and passes
 * against the paged one.
 */

import { describe, it, expect, beforeEach } from "vitest";
import type * as adminTypes from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  EXPIRY_FLIP_PAGE_SIZE,
  flipExpiredDocuments,
} from "./retentionCore";

const NOW = 1_800_000_000_000;
const DAY = 24 * 60 * 60 * 1000;
const EXPIRED = NOW - DAY;
const FUTURE = NOW + DAY;

let db: FakeFirestore;

function asFirestore(fake: FakeFirestore): adminTypes.firestore.Firestore {
  return fake as unknown as adminTypes.firestore.Firestore;
}

beforeEach(() => {
  db = new FakeFirestore();
});

/** The `invites` flip exactly as `expiration.ts` configures it. */
async function flipInvites(overrides: Record<string, unknown> = {}) {
  return flipExpiredDocuments(asFirestore(db), {
    collection: "invites",
    match: { field: "status", value: "pending" },
    timestampField: "expiresAt",
    cutoff: NOW,
    update: { status: "expired" },
    ...overrides,
  });
}

describe("flipExpiredDocuments: what it flips", () => {
  it("flips only pending rows whose expiry has passed", async () => {
    db.seed("invites/lapsed", { status: "pending", expiresAt: EXPIRED });
    db.seed("invites/still-live", { status: "pending", expiresAt: FUTURE });
    db.seed("invites/already-declined", { status: "declined", expiresAt: EXPIRED });

    const result = await flipInvites();

    expect(result.flipped).toBe(1);
    expect(result.truncated).toBe(false);
    expect(db.store.get("invites/lapsed")!.status).toBe("expired");
    expect(db.store.get("invites/still-live")!.status).toBe("pending");
    expect(db.store.get("invites/already-declined")!.status).toBe("declined");
  });

  it("cannot see a row with no expiresAt at all", async () => {
    db.seed("invites/no-expiry", { status: "pending" });
    const result = await flipInvites();
    expect(result.scanned).toBe(0);
    expect(db.store.get("invites/no-expiry")!.status).toBe("pending");
  });

  it("carries the caller's extra update fields through", async () => {
    db.seed("trip_invites/lapsed", { status: "pending", expiresAt: EXPIRED });

    await flipExpiredDocuments(asFirestore(db), {
      collection: "trip_invites",
      match: { field: "status", value: "pending" },
      timestampField: "expiresAt",
      cutoff: NOW,
      update: { status: "expired", respondedAt: "__serverTimestamp__" },
    });

    expect(db.store.get("trip_invites/lapsed")).toEqual({
      status: "expired",
      expiresAt: EXPIRED,
      respondedAt: "__serverTimestamp__",
    });
  });

  it("handles a non-status match field (share codes flip isRevoked)", async () => {
    db.seed("share_codes/lapsed", { isRevoked: false, expiresAt: EXPIRED });
    db.seed("share_codes/already-revoked", { isRevoked: true, expiresAt: EXPIRED });

    const result = await flipExpiredDocuments(asFirestore(db), {
      collection: "share_codes",
      match: { field: "isRevoked", value: false },
      timestampField: "expiresAt",
      cutoff: NOW,
      update: { isRevoked: true },
    });

    expect(result.flipped).toBe(1);
    expect(db.store.get("share_codes/lapsed")!.isRevoked).toBe(true);
  });
});

describe("flipExpiredDocuments: bounded, not one giant batch (L-7)", () => {
  it("flips more rows than a single WriteBatch could ever hold", async () => {
    const total = EXPIRY_FLIP_PAGE_SIZE + 200; // 600 — well past the 500-op batch cap
    for (let i = 0; i < total; i += 1) {
      db.seed(`invites/inv-${String(i).padStart(4, "0")}`, {
        status: "pending",
        expiresAt: EXPIRED,
      });
    }

    const result = await flipInvites();

    expect(result.flipped).toBe(total);
    expect(result.truncated).toBe(false);
    const stillPending = db.docPathsMatching(
      (path, data) => path.startsWith("invites/") && data.status === "pending"
    );
    expect(stillPending).toEqual([]);
  });

  it("stops at maxFlips, reports truncation, and the next run resumes", async () => {
    for (let i = 0; i < 5; i += 1) {
      db.seed(`invites/inv-${i}`, { status: "pending", expiresAt: EXPIRED });
    }

    const first = await flipInvites({ pageSize: 2, maxFlips: 2 });
    expect(first.flipped).toBe(2);
    expect(first.truncated).toBe(true);

    const second = await flipInvites({ pageSize: 2, maxFlips: 100 });
    expect(second.flipped).toBe(3);
    expect(second.truncated).toBe(false);
  });

  it("is self-quenching: a second run over a clean collection writes nothing", async () => {
    db.seed("invites/lapsed", { status: "pending", expiresAt: EXPIRED });
    await flipInvites();

    db.writeCount = 0;
    const second = await flipInvites();

    expect(second.scanned).toBe(0);
    expect(second.flipped).toBe(0);
    expect(db.writeCount).toBe(0);
  });
});
