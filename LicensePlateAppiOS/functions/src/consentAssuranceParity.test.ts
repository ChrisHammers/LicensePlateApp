/**
 * FR-108(a) parity — the consent assurance lattice is pinned by a closed enum in BOTH
 * runtimes, progression-catalog discipline: one canonical JSON, byte-identical in both
 * trees, each runtime's suite pinning its own policy against its copy.
 *
 * The chain: Swift `ConsentAssurancePolicy` == iOS JSON (ConsentAssuranceLatticeParityTests)
 * ⟷ iOS JSON == functions JSON (byte compare here) ⟷ functions JSON == TS
 * `CONSENT_ASSURANCE_LEVELS` (here). Drift anywhere fails a suite. The JSON is a test
 * fixture only — neither runtime loads it at runtime, so there is no fallback path to
 * mask a missing file (a missing fixture fails parity, as it must).
 */

import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";
import {
  CONSENT_ASSURANCE_LEVELS,
  REQUIRED_CONSENT_LEVEL,
} from "./consentRequestsCore";

const here = dirname(fileURLToPath(import.meta.url));
const iosLatticePath = join(
  here,
  "../../LicensePlateApp/Resources/ConsentAssuranceLattice.v1.json"
);
const functionsLatticePath = join(here, "consentAssuranceLattice.v1.json");

describe("consentAssuranceParity (FR-108(a))", () => {
  it("iOS bundled lattice matches the functions copy byte-for-byte", () => {
    const iosBytes = readFileSync(iosLatticePath);
    const functionsBytes = readFileSync(functionsLatticePath);
    expect(functionsBytes.equals(iosBytes)).toBe(true);
  });

  it("the TS runtime lattice IS the canonical lattice, both directions", () => {
    const canonical = JSON.parse(readFileSync(functionsLatticePath, "utf8"));
    expect({ ...CONSENT_ASSURANCE_LEVELS }).toEqual(canonical.methods);
    expect(REQUIRED_CONSENT_LEVEL).toBe(canonical.requiredLevel);
  });
});
