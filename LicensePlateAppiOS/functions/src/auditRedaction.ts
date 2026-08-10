/**
 * Redaction helpers for `audit_logs` metadata (COPPA G2 / FR-50).
 *
 * Audit rows outlive the accounts they describe, so they must never carry raw user-supplied
 * strings: family names routinely embed surnames, and search queries are usernames, emails
 * and phone numbers by definition. Store a hash instead — enough to tell whether two rows
 * concern the same value, nothing an operator or a leak can read back.
 *
 * Firestore-free on purpose so the pure modules (userSearchCore) can use it too.
 */

import { createHash } from "crypto";

/** Truncated to 16 hex chars: still collision-free at audit-log scale, not a rainbow-table key. */
const AUDIT_HASH_LENGTH = 16;

/**
 * Stable, non-reversible stand-in for a user-supplied string.
 * Returns null for anything that is not a non-empty string, so callers can drop the field.
 */
export function auditValueHash(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (!normalized) return null;
  return createHash("sha256").update(normalized).digest("hex").slice(0, AUDIT_HASH_LENGTH);
}
