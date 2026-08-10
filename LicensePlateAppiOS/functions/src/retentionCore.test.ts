import { describe, it, expect } from "vitest";
import * as admin from "firebase-admin";
import {
  AUDIT_LOG_COLLECTION,
  AUDIT_LOG_RETENTION_MONTHS,
  AUDIT_RETENTION_EXEMPT_EVENT_TYPES,
  EXPIRED_RECORD_DELETION_GRACE_DAYS,
  FRIEND_INVITE_EXPIRY_DAYS,
  PURGEABLE_EXPIRY_COLLECTIONS,
  RETENTION_DELETE_BATCH_SIZE,
  auditRetentionCutoffMillis,
  expiredRecordDeletionCutoffMillis,
  friendInviteExpiresAtMillis,
  isAuditRetentionExempt,
  purgeDocumentsOlderThan,
} from "./retentionCore";

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 7, 10, 12, 0, 0);

// ---------------------------------------------------------------------------
// Minimal in-memory Firestore double. Supports exactly the surface
// purgeDocumentsOlderThan uses: where(<) + orderBy + limit + startAfter + get,
// and batched deletes.
// ---------------------------------------------------------------------------

interface Row {
  id: string;
  data: Record<string, unknown>;
}

function millisOf(value: unknown): number {
  if (value && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    return (value as { toMillis: () => number }).toMillis();
  }
  return Number(value);
}

function makeFakeDb(seed: Record<string, Row[]>) {
  const store: Record<string, Row[]> = {};
  for (const [name, rows] of Object.entries(seed)) {
    store[name] = rows.map((r) => ({ id: r.id, data: { ...r.data } }));
  }

  const stats = { commits: 0, queries: 0, maxBatchSize: 0 };

  interface QueryState {
    collection: string;
    field?: string;
    cutoff?: number;
    limit?: number;
    afterId?: string;
  }

  function makeQuery(state: QueryState): unknown {
    const self = {
      where(field: string, op: string, value: unknown) {
        expect(op).toBe("<");
        return makeQuery({ ...state, field, cutoff: millisOf(value) });
      },
      orderBy(field: string, direction: string) {
        expect(field).toBe(state.field);
        expect(direction).toBe("asc");
        return self;
      },
      limit(n: number) {
        return makeQuery({ ...state, limit: n });
      },
      startAfter(doc: { id: string }) {
        return makeQuery({ ...state, afterId: doc.id });
      },
      async get() {
        stats.queries += 1;
        const field = state.field!;
        let rows = (store[state.collection] ?? [])
          .filter((r) => r.data[field] !== undefined)
          .filter((r) => millisOf(r.data[field]) < state.cutoff!)
          // Firestore orders by the range field, then by document name.
          .sort((a, b) => {
            const delta = millisOf(a.data[field]) - millisOf(b.data[field]);
            return delta !== 0 ? delta : a.id.localeCompare(b.id);
          });

        if (state.afterId !== undefined) {
          const idx = rows.findIndex((r) => r.id === state.afterId);
          // A deleted cursor doc still positions the query by its field values;
          // fall back to a value comparison when the row is gone.
          rows = idx >= 0 ? rows.slice(idx + 1) : rows;
        }
        if (state.limit !== undefined) {
          rows = rows.slice(0, state.limit);
        }

        const docs = rows.map((r) => ({
          id: r.id,
          ref: { id: r.id, collection: state.collection },
          data: () => r.data,
        }));
        return { empty: docs.length === 0, size: docs.length, docs };
      },
    };
    return self;
  }

  const db = {
    collection(name: string) {
      return makeQuery({ collection: name });
    },
    batch() {
      const pending: { id: string; collection: string }[] = [];
      return {
        delete(ref: { id: string; collection: string }) {
          pending.push(ref);
        },
        async commit() {
          stats.commits += 1;
          stats.maxBatchSize = Math.max(stats.maxBatchSize, pending.length);
          expect(pending.length).toBeLessThanOrEqual(500);
          for (const ref of pending) {
            store[ref.collection] = (store[ref.collection] ?? []).filter(
              (r) => r.id !== ref.id
            );
          }
          return [];
        },
      };
    },
  };

  return {
    db: db as unknown as admin.firestore.Firestore,
    stats,
    idsIn: (name: string) => (store[name] ?? []).map((r) => r.id).sort(),
  };
}

function ts(millis: number): unknown {
  return { toMillis: () => millis };
}

// ---------------------------------------------------------------------------

describe("retention policy constants", () => {
  it("uses the documented defaults", () => {
    expect(FRIEND_INVITE_EXPIRY_DAYS).toBe(30);
    expect(EXPIRED_RECORD_DELETION_GRACE_DAYS).toBe(30);
    expect(AUDIT_LOG_RETENTION_MONTHS).toBe(12);
    expect(RETENTION_DELETE_BATCH_SIZE).toBeLessThan(500);
  });

  it("purges only transient collections, never gameplay history", () => {
    expect([...PURGEABLE_EXPIRY_COLLECTIONS].sort()).toEqual([
      "invites",
      "share_codes",
      "trip_invites",
    ]);
    expect(PURGEABLE_EXPIRY_COLLECTIONS).not.toContain("trip_sessions");
    expect(PURGEABLE_EXPIRY_COLLECTIONS).not.toContain("activity_events");
  });
});

describe("friend invite finite expiry (FR-49b)", () => {
  it("expires 30 days out, not 100 years", () => {
    expect(friendInviteExpiresAtMillis(NOW)).toBe(NOW + 30 * MS_PER_DAY);
  });

  it("never produces a sentinel far-future expiry", () => {
    const horizonDays = (friendInviteExpiresAtMillis(NOW) - NOW) / MS_PER_DAY;
    expect(horizonDays).toBeGreaterThan(0);
    expect(horizonDays).toBeLessThanOrEqual(366);
  });

  it("lapsed friend invites become deletable one grace period later", () => {
    const expiresAt = friendInviteExpiresAtMillis(NOW);
    // Still protected the day it expires...
    expect(expiredRecordDeletionCutoffMillis(expiresAt)).toBeLessThan(expiresAt);
    // ...and eligible once the grace period has run.
    const later = expiresAt + EXPIRED_RECORD_DELETION_GRACE_DAYS * MS_PER_DAY + 1;
    expect(expiredRecordDeletionCutoffMillis(later)).toBeGreaterThan(expiresAt);
  });
});

describe("retention cutoffs", () => {
  it("expired-record cutoff defaults to a 30 day grace period", () => {
    expect(expiredRecordDeletionCutoffMillis(NOW)).toBe(NOW - 30 * MS_PER_DAY);
    expect(expiredRecordDeletionCutoffMillis(NOW, 7)).toBe(NOW - 7 * MS_PER_DAY);
  });

  it("audit cutoff defaults to twelve calendar months in UTC", () => {
    expect(auditRetentionCutoffMillis(NOW)).toBe(Date.UTC(2025, 7, 10, 12, 0, 0));
    expect(auditRetentionCutoffMillis(NOW, 1)).toBe(Date.UTC(2026, 6, 10, 12, 0, 0));
  });
});

describe("purgeDocumentsOlderThan — grace period boundaries", () => {
  const cutoff = expiredRecordDeletionCutoffMillis(NOW); // NOW - 30d

  function seedInvites() {
    return makeFakeDb({
      invites: [
        { id: "long_gone", data: { expiresAt: ts(NOW - 400 * MS_PER_DAY) } },
        { id: "just_past_grace", data: { expiresAt: ts(cutoff - 1) } },
        { id: "exactly_at_cutoff", data: { expiresAt: ts(cutoff) } },
        { id: "inside_grace", data: { expiresAt: ts(NOW - 29 * MS_PER_DAY) } },
        { id: "not_yet_expired", data: { expiresAt: ts(NOW + MS_PER_DAY) } },
        { id: "no_expiry_field", data: { status: "pending" } },
      ],
    });
  }

  it("deletes only records whose expiry passed more than the grace period ago", async () => {
    const fake = seedInvites();
    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: "invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
    });

    expect(result.deleted).toBe(2);
    expect(result.exempt).toBe(0);
    expect(result.truncated).toBe(false);
    expect(fake.idsIn("invites")).toEqual([
      "exactly_at_cutoff",
      "inside_grace",
      "no_expiry_field",
      "not_yet_expired",
    ]);
  });

  it("is idempotent — a second run deletes nothing and commits nothing", async () => {
    const fake = seedInvites();
    await purgeDocumentsOlderThan(fake.db, {
      collection: "invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
    });
    const survivors = fake.idsIn("invites");
    const commitsAfterFirstRun = fake.stats.commits;

    const second = await purgeDocumentsOlderThan(fake.db, {
      collection: "invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
    });

    expect(second.deleted).toBe(0);
    expect(second.scanned).toBe(0);
    expect(fake.stats.commits).toBe(commitsAfterFirstRun);
    expect(fake.idsIn("invites")).toEqual(survivors);
  });

  it("handles an empty collection", async () => {
    const fake = makeFakeDb({});
    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: "share_codes",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
    });
    expect(result).toMatchObject({ scanned: 0, deleted: 0, truncated: false });
    expect(fake.stats.commits).toBe(0);
  });

  it("pages deletes within the Firestore batch limit", async () => {
    const rows: Row[] = [];
    for (let i = 0; i < 950; i++) {
      rows.push({
        id: `doc_${String(i).padStart(4, "0")}`,
        data: { expiresAt: ts(cutoff - 1000 - i) },
      });
    }
    const fake = makeFakeDb({ trip_invites: rows });

    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: "trip_invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
    });

    expect(result.deleted).toBe(950);
    expect(fake.idsIn("trip_invites")).toEqual([]);
    expect(fake.stats.maxBatchSize).toBeLessThanOrEqual(RETENTION_DELETE_BATCH_SIZE);
    expect(fake.stats.commits).toBe(3);
  });

  it("stops at maxDeletes and reports truncation for the next run", async () => {
    const rows: Row[] = [];
    for (let i = 0; i < 10; i++) {
      rows.push({ id: `d${i}`, data: { expiresAt: ts(cutoff - 1000 - i) } });
    }
    const fake = makeFakeDb({ invites: rows });

    const first = await purgeDocumentsOlderThan(fake.db, {
      collection: "invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
      batchSize: 4,
      maxDeletes: 4,
    });
    expect(first.deleted).toBe(4);
    expect(first.truncated).toBe(true);

    const second = await purgeDocumentsOlderThan(fake.db, {
      collection: "invites",
      timestampField: "expiresAt",
      cutoffMillis: cutoff,
      batchSize: 4,
    });
    expect(second.deleted).toBe(6);
    expect(fake.idsIn("invites")).toEqual([]);
  });
});

describe("audit_logs retention with consent carve-out (FR-49c / G-7)", () => {
  const cutoff = auditRetentionCutoffMillis(NOW);
  const ancient = ts(NOW - 5 * 365 * MS_PER_DAY);
  const isExempt = (data: admin.firestore.DocumentData) =>
    isAuditRetentionExempt(data.eventType);

  it("pins the exempt event type list", () => {
    // Changing this list changes what parental-consent evidence survives retention.
    expect([...AUDIT_RETENTION_EXEMPT_EVENT_TYPES]).toEqual([
      "AUDIT_PARENTAL_CONSENT_GRANTED",
      "AUDIT_PARENTAL_CONSENT_CORRECTED",
      "AUDIT_PARENTAL_CONSENT_REVOKED",
      "AUDIT_CHILD_REGISTRATION_DECLARED",
      "AUDIT_ACCOUNT_DELETED",
    ]);
  });

  it("classifies exempt vs. ordinary event types", () => {
    for (const eventType of AUDIT_RETENTION_EXEMPT_EVENT_TYPES) {
      expect(isAuditRetentionExempt(eventType)).toBe(true);
    }
    expect(isAuditRetentionExempt("AUDIT_FRIEND_REQUEST_SENT")).toBe(false);
    expect(isAuditRetentionExempt("share_code_generated")).toBe(false);
    expect(isAuditRetentionExempt(undefined)).toBe(false);
    expect(isAuditRetentionExempt(null)).toBe(false);
    expect(isAuditRetentionExempt(42)).toBe(false);
  });

  it("deletes rows older than the window and keeps recent ones", async () => {
    const fake = makeFakeDb({
      [AUDIT_LOG_COLLECTION]: [
        { id: "old_1", data: { eventType: "AUDIT_FRIEND_REQUEST_SENT", createdAt: ts(cutoff - MS_PER_DAY) } },
        { id: "old_2", data: { eventType: "share_code_used", createdAt: ancient } },
        { id: "at_cutoff", data: { eventType: "share_code_used", createdAt: ts(cutoff) } },
        { id: "recent", data: { eventType: "AUDIT_FRIENDSHIP_ACCEPTED", createdAt: ts(NOW - MS_PER_DAY) } },
      ],
    });

    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: AUDIT_LOG_COLLECTION,
      timestampField: "createdAt",
      cutoffMillis: cutoff,
      isExempt,
    });

    expect(result.deleted).toBe(2);
    expect(result.exempt).toBe(0);
    expect(fake.idsIn(AUDIT_LOG_COLLECTION)).toEqual(["at_cutoff", "recent"]);
  });

  it("never deletes consent or lifecycle evidence, however old", async () => {
    const exemptRows: Row[] = AUDIT_RETENTION_EXEMPT_EVENT_TYPES.map((eventType) => ({
      id: `exempt_${eventType}`,
      data: { eventType, createdAt: ancient },
    }));
    const fake = makeFakeDb({
      [AUDIT_LOG_COLLECTION]: [
        ...exemptRows,
        { id: "purge_me", data: { eventType: "AUDIT_TRIP_INVITE_SENT", createdAt: ancient } },
      ],
    });

    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: AUDIT_LOG_COLLECTION,
      timestampField: "createdAt",
      cutoffMillis: cutoff,
      isExempt,
    });

    expect(result.deleted).toBe(1);
    expect(result.exempt).toBe(AUDIT_RETENTION_EXEMPT_EVENT_TYPES.length);
    expect(fake.idsIn(AUDIT_LOG_COLLECTION)).toEqual(
      exemptRows.map((r) => r.id).sort()
    );
  });

  it("terminates when a whole page is exempt (cursor advances past survivors)", async () => {
    const rows: Row[] = [];
    for (let i = 0; i < 6; i++) {
      rows.push({
        id: `exempt_${i}`,
        data: {
          eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
          createdAt: ts(cutoff - 10_000 + i),
        },
      });
    }
    rows.push({
      id: "zz_deletable",
      data: { eventType: "family_join_request_created", createdAt: ts(cutoff - 1) },
    });
    const fake = makeFakeDb({ [AUDIT_LOG_COLLECTION]: rows });

    const result = await purgeDocumentsOlderThan(fake.db, {
      collection: AUDIT_LOG_COLLECTION,
      timestampField: "createdAt",
      cutoffMillis: cutoff,
      isExempt,
      batchSize: 2,
    });

    expect(result.deleted).toBe(1);
    expect(result.exempt).toBe(6);
    expect(fake.idsIn(AUDIT_LOG_COLLECTION)).toEqual(rows.slice(0, 6).map((r) => r.id));
  });

  it("is idempotent — rerunning re-reads exempt rows but deletes nothing", async () => {
    const fake = makeFakeDb({
      [AUDIT_LOG_COLLECTION]: [
        { id: "consent", data: { eventType: "AUDIT_PARENTAL_CONSENT_GRANTED", createdAt: ancient } },
        { id: "stale", data: { eventType: "friend_request_declined", createdAt: ancient } },
      ],
    });
    const options = {
      collection: AUDIT_LOG_COLLECTION,
      timestampField: "createdAt",
      cutoffMillis: cutoff,
      isExempt,
    };

    const first = await purgeDocumentsOlderThan(fake.db, options);
    const second = await purgeDocumentsOlderThan(fake.db, options);

    expect(first.deleted).toBe(1);
    expect(second.deleted).toBe(0);
    expect(second.exempt).toBe(1);
    expect(fake.idsIn(AUDIT_LOG_COLLECTION)).toEqual(["consent"]);
  });
});
