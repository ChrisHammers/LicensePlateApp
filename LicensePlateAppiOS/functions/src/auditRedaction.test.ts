import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import { auditValueHash } from "./auditRedaction";
import { auditQueryFingerprint } from "./userSearchCore";

describe("auditValueHash", () => {
  it("is deterministic and normalized", () => {
    expect(auditValueHash("The Smiths")).toBe(auditValueHash("  the smiths  "));
  });

  it("is a short hex digest, never the input", () => {
    const hash = auditValueHash("The Smith Family")!;
    expect(hash).toMatch(/^[0-9a-f]{16}$/);
    expect(hash.toLowerCase()).not.toContain("smith");
  });

  it("distinguishes different values", () => {
    expect(auditValueHash("Smith")).not.toBe(auditValueHash("Jones"));
  });

  it("returns null for anything unusable so callers drop the field", () => {
    expect(auditValueHash("")).toBeNull();
    expect(auditValueHash("   ")).toBeNull();
    expect(auditValueHash(undefined)).toBeNull();
    expect(auditValueHash(null)).toBeNull();
    expect(auditValueHash(42)).toBeNull();
  });
});

describe("auditQueryFingerprint", () => {
  const cases: { kind: "email" | "phone" | "username"; query: string; secrets: string[] }[] = [
    { kind: "email", query: "john.doe@example.com", secrets: ["john", "doe", "example.com"] },
    { kind: "phone", query: "(203) 555-1111", secrets: ["203", "555", "1111"] },
    { kind: "username", query: "RoadTripKid2015", secrets: ["roadtrip", "kid", "2015"] },
  ];

  it("keeps the kind and a truncated SHA-256, nothing else", () => {
    for (const { kind, query } of cases) {
      expect(auditQueryFingerprint(kind, query)).toMatch(
        new RegExp(`^${kind}:[0-9a-f]{16}$`)
      );
    }
  });

  it("leaks no plaintext for any modality", () => {
    for (const { kind, query, secrets } of cases) {
      const fingerprint = auditQueryFingerprint(kind, query).toLowerCase();
      for (const secret of secrets) {
        expect(fingerprint, `${kind} leaked "${secret}"`).not.toContain(secret);
      }
    }
  });

  it("is stable across equivalent spellings and distinct across queries", () => {
    expect(auditQueryFingerprint("username", "RoadTrip")).toBe(
      auditQueryFingerprint("username", " roadtrip ")
    );
    expect(auditQueryFingerprint("username", "alice")).not.toBe(
      auditQueryFingerprint("username", "bob")
    );
  });
});

/**
 * Guard for audit-log PII hygiene: audit rows outlive the accounts they describe, so a raw
 * `familyName` must never be written into one again (family names embed surnames).
 */
describe("audit metadata PII lint", () => {
  const srcDir = join(__dirname);
  const files = readdirSync(srcDir).filter(
    (f) => f.endsWith(".ts") && !f.endsWith(".test.ts")
  );

  it("never writes a plaintext familyName as an object key", () => {
    const offenders: string[] = [];
    for (const file of files) {
      const lines = readFileSync(join(srcDir, file), "utf8").split("\n");
      lines.forEach((line, i) => {
        if (/^\s*familyName\s*:/.test(line)) {
          offenders.push(`${file}:${i + 1}`);
        }
      });
    }
    expect(offenders).toEqual([]);
  });

  it("hashes the family name at every audit call site that used to log it", () => {
    const hashed = files.filter((file) =>
      /familyNameHash:\s*auditValueHash\(/.test(readFileSync(join(srcDir, file), "utf8"))
    );
    expect(hashed.sort()).toEqual(["accountDeletion.ts", "auth.ts", "family.ts"]);
  });
});
