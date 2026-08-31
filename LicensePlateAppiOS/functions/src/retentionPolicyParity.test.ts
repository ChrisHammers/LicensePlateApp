/**
 * FR-77 acceptance: constants ↔ NP-3 policy-text parity, pinned (the FR-83
 * consent-version test pattern). If a retention window changes in code without the
 * written policy changing — or vice versa — this fails the suite.
 *
 * Reads `RETENTION_POLICY.md` at the repo root and asserts each ENFORCED class's row
 * states the window the shipped constant enforces. The adopted-but-unbuilt rows
 * (11–12) join this test when their constants exist.
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS } from "./provisionalChildAccounts";
import { REVOKED_CHILD_RETENTION_DAYS_DEFAULT } from "./revokedChildRetention";
import { CONSENT_REQUEST_TTL_MS } from "./consentRequestsCore";
import {
  AUDIT_LOG_RETENTION_MONTHS,
  EXPIRED_RECORD_DELETION_GRACE_DAYS,
} from "./retentionCore";

const policyPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../RETENTION_POLICY.md"
);
const policy = readFileSync(policyPath, "utf8");

/** The schedule-table row whose data-class label contains `label`. */
function scheduleRow(label: string): string {
  const row = policy
    .split("\n")
    .find((line) => line.startsWith("|") && line.includes(label));
  expect(row, `RETENTION_POLICY.md must have a schedule row for "${label}"`).toBeDefined();
  return row as string;
}

describe("NP-3 ↔ code parity (FR-77 acceptance)", () => {
  it("redemption-window backstop states the shipped 7-day window", () => {
    expect(PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS).toBe(7);
    expect(scheduleRow("Redemption-window child accounts")).toContain(
      `**${PROVISIONAL_CHILD_REDEMPTION_WINDOW_DAYS}-day**`
    );
  });

  it("consent requests state the shipped 72-hour TTL", () => {
    const ttlHours = CONSENT_REQUEST_TTL_MS / (60 * 60 * 1000);
    expect(ttlHours).toBe(72);
    expect(scheduleRow("Consent requests")).toContain(`**${ttlHours} hours**`);
  });

  it("revoked-child retention states the OD-3 twelve months, enforced as 365 days", () => {
    // The policy speaks months; the sweep counts days. 12 months ⇔ 365 days is the
    // recorded equivalence — a change to either side must touch both.
    expect(REVOKED_CHILD_RETENTION_DAYS_DEFAULT).toBe(365);
    expect(scheduleRow("Revoked-but-retained child accounts")).toContain("**12 months**");
  });

  it("invite/share-code grace states the shipped 30 days", () => {
    expect(EXPIRED_RECORD_DELETION_GRACE_DAYS).toBe(30);
    expect(scheduleRow("Invites and share codes")).toContain(
      `**${EXPIRED_RECORD_DELETION_GRACE_DAYS} days**`
    );
  });

  it("general audit-log retention states the shipped 12 months", () => {
    expect(AUDIT_LOG_RETENTION_MONTHS).toBe(12);
    expect(scheduleRow("Audit logs (general)")).toContain(
      `**${AUDIT_LOG_RETENTION_MONTHS} months**`
    );
  });

  it("the consent-evidence exemption is stated with its rationale", () => {
    const row = scheduleRow("Consent and lifecycle audit records");
    expect(row).toContain("Exempt from purging");
    expect(row).toContain("proof of compliance");
  });
});
