/**
 * FR-65 / FR-103 parity — the consent scope catalog is pinned in BOTH runtimes,
 * lattice discipline: one canonical JSON, byte-identical in both trees, each
 * runtime's suite pinning its own constants against its copy.
 *
 * The chain: Swift `ConsentScopeId` / `ConsentScopeCatalog` == iOS test JSON
 * (ConsentScopeCatalogParityTests) ⟷ iOS test JSON == functions JSON (byte compare
 * here) ⟷ functions JSON == TS `CONSENT_SCOPE_*` and `CONSENT_TEXT_VERSION` (here).
 * Drift anywhere fails a suite. The JSON is a test fixture only — neither runtime
 * loads it, so a missing file fails parity rather than passing silently.
 */

import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";
import {
  CONSENT_SCOPE_CATALOG,
  CONSENT_SCOPE_IDS,
  CONSENT_SCOPE_PRACTICE_VERSIONS,
  CONSENT_TEXT_VERSION,
} from "./childAccountCore";

const here = dirname(fileURLToPath(import.meta.url));
const iosCatalogPath = join(here, "../../LicensePlateAppTests/ConsentScopeCatalog.v1.json");
const functionsCatalogPath = join(here, "consentScopeCatalog.v1.json");

interface CanonicalCatalog {
  schema: number;
  consentTextVersion: string;
  scopes: { id: string; availability: string; practiceVersion: number; policyAnchor: string }[];
}

function loadCanonical(): CanonicalCatalog {
  return JSON.parse(readFileSync(functionsCatalogPath, "utf8")) as CanonicalCatalog;
}

describe("consentScopeParity (FR-65 / FR-103)", () => {
  it("the iOS test fixture matches the functions copy byte-for-byte", () => {
    const iosBytes = readFileSync(iosCatalogPath);
    const functionsBytes = readFileSync(functionsCatalogPath);
    expect(functionsBytes.equals(iosBytes)).toBe(true);
  });

  it("is schema 1", () => {
    expect(loadCanonical().schema).toBe(1);
  });

  it("the TS scope ids, order, availability and anchors ARE the canonical catalog", () => {
    const canonical = loadCanonical();
    expect(canonical.scopes.map((s) => s.id)).toEqual([...CONSENT_SCOPE_IDS]);
    expect(
      canonical.scopes.map(({ id, availability, policyAnchor }) => ({
        id,
        availability,
        policyAnchor,
      }))
    ).toEqual(CONSENT_SCOPE_CATALOG.map((entry) => ({ ...entry })));
  });

  it("the TS practice versions ARE the canonical ones, both directions", () => {
    const canonical = loadCanonical();
    expect({ ...CONSENT_SCOPE_PRACTICE_VERSIONS }).toEqual(
      Object.fromEntries(canonical.scopes.map((s) => [s.id, s.practiceVersion]))
    );
  });

  // Moves with every CONSENT_TEXT_VERSION bump: the fixture, this constant and the
  // Swift `ConsentScopeCatalog.consentTextVersion` change in the same commit.
  it("the fixture carries the current CONSENT_TEXT_VERSION", () => {
    expect(loadCanonical().consentTextVersion).toBe(CONSENT_TEXT_VERSION);
  });
});
