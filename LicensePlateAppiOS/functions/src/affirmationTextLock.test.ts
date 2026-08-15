import { createHash } from "crypto";
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";
import { AFFIRMATION_TEXT_HASH, AFFIRMATION_VERSION, CONSENT_TEXT_VERSION } from "./childAccountCore";

/**
 * Consent-version lock (COPPA FR-83e).
 *
 * `AFFIRMATION_VERSION` / `CONSENT_TEXT_VERSION` (childAccountCore.ts) are the durable
 * evidence of exactly which wording a parent consented to (FR-31) — they are stamped
 * onto every consent-granted audit row and are meant to be hand-bumped whenever the
 * localized guardian-affirmation copy changes. Nothing enforced that discipline. This
 * test recomputes a hash of the LIVE localized strings on every run and compares it
 * against `AFFIRMATION_TEXT_HASH`, recorded alongside the versions in
 * childAccountCore.ts — so an un-bumped copy edit fails the suite instead of silently
 * invalidating the version pin on future consent-evidence rows.
 */

const AFFIRMATION_KEY = "family.child.guardian_affirmation";
const LOCALES = ["en", "es", "fr"] as const;

const here = dirname(fileURLToPath(import.meta.url));

/** Minimal `.strings` value extractor — handles \" \\ \n escapes, nothing fancier. */
function extractLocalizedValue(locale: string, key: string): string {
  const path = join(here, `../../LicensePlateApp/${locale}.lproj/Localizable.strings`);
  const contents = readFileSync(path, "utf8");
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`"${escapedKey}"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*;`);
  const match = contents.match(pattern);
  if (!match) {
    throw new Error(
      `affirmationTextLock: could not find "${key}" in ${locale}.lproj/Localizable.strings. ` +
        "If the key was renamed, update AFFIRMATION_KEY in this test to match."
    );
  }
  return match[1].replace(/\\"/g, '"').replace(/\\n/g, "\n").replace(/\\\\/g, "\\");
}

function hashAffirmationStrings(): { hash: string; values: readonly string[] } {
  const values = LOCALES.map((locale) => extractLocalizedValue(locale, AFFIRMATION_KEY));
  const hash = createHash("sha256").update(JSON.stringify(values)).digest("hex");
  return { hash, values };
}

describe("consent-version lock (FR-83e)", () => {
  it("AFFIRMATION_TEXT_HASH matches the live en/es/fr guardian-affirmation copy", () => {
    const { hash, values } = hashAffirmationStrings();

    if (hash !== AFFIRMATION_TEXT_HASH) {
      throw new Error(
        "The localized `family.child.guardian_affirmation` string (en/es/fr .lproj/Localizable.strings) " +
          "no longer matches AFFIRMATION_TEXT_HASH recorded in childAccountCore.ts. This sentence is " +
          "consent evidence (FR-31) — if you intentionally changed the wording, bump BOTH " +
          "AFFIRMATION_VERSION and CONSENT_TEXT_VERSION in childAccountCore.ts, then update " +
          `AFFIRMATION_TEXT_HASH to the newly computed hash below, all in the SAME commit.\n` +
          `  current strings: ${JSON.stringify(values)}\n` +
          `  newly computed hash: ${hash}\n` +
          `  recorded AFFIRMATION_TEXT_HASH: ${AFFIRMATION_TEXT_HASH}`
      );
    }

    expect(hash).toBe(AFFIRMATION_TEXT_HASH);
  });

  it("AFFIRMATION_VERSION and CONSENT_TEXT_VERSION are non-empty version stamps", () => {
    expect(AFFIRMATION_VERSION.length).toBeGreaterThan(0);
    expect(CONSENT_TEXT_VERSION.length).toBeGreaterThan(0);
  });
});
