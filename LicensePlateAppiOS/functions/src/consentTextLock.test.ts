import { createHash } from "crypto";
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";
import { CONSENT_TEXT_HASH, CONSENT_TEXT_VERSION } from "./childAccountCore";

/**
 * Consent-text lock (F-21 / FR-103, versionBump counter 1).
 *
 * CONSENT_TEXT_VERSION is what the captain's app sends and the server equality-gates; it
 * is stamped on every consent request and copied into the GRANTED row as the evidence of
 * which wording the captain was shown. It covers ONLY app-shown text: the consent cards
 * (every `family.consent_scope.*` key), the two acknowledgment strings and the Privacy
 * Policy §12 subsections, in en/es/fr. This test hashes the LIVE values of exactly those
 * keys from the three `Localizable.strings` files, in the fixed order below, and compares
 * the hash with CONSENT_TEXT_HASH — so editing any of them without bumping the version
 * fails the suite.
 *
 * Deliberately NOT covered: `privacy.last_updated` (the policy date; CONSENT_POLICY_VERSIONS
 * pins the policy) and `family.child.inventory.vendor_analytics` (the manage screen's
 * third-party line, not consent text). The guardian affirmation has its own lock
 * (`affirmationTextLock.test.ts`).
 */

const LOCALES = ["en", "es", "fr"] as const;

/**
 * Hash order. Fixed here, never file order. Deck order, except the two acknowledgment
 * keys follow the family.consent_scope.* block.
 */
const CONSENT_TEXT_KEYS: readonly string[] = [
  "family.consent_scope.section_title",
  "family.consent_scope.section_intro",
  "family.consent_scope.core.name",
  "family.consent_scope.core.meaning",
  "family.consent_scope.core.collected",
  "family.consent_scope.core.who_sees",
  "family.consent_scope.core.notifications",
  "family.consent_scope.core.required_reason.join",
  "family.consent_scope.core.required_reason.member_flag",
  "family.consent_scope.state.required",
  "family.consent_scope.state.agreed",
  "family.consent_scope.state.unavailable",
  "family.consent_scope.frozen_reason",
  "family.consent_scope.analytics_internal.name",
  "family.consent_scope.analytics_internal.meaning",
  "family.consent_scope.analytics_internal.collected",
  "family.consent_scope.ads_child_directed.name",
  "family.consent_scope.ads_child_directed.meaning",
  "family.consent_scope.ads_child_directed.collected",
  "family.consent_scope.location_family_shared.name",
  "family.consent_scope.location_family_shared.meaning",
  "family.consent_scope.location_family_shared.collected",
  "family.consent_scope.cross_family_visibility.name",
  "family.consent_scope.cross_family_visibility.meaning",
  "family.consent_scope.cross_family_visibility.collected",
  "family.consent_scope.who_sees_nobody",
  "family.consent_scope.cross_family_visibility.who_sees",
  "family.consent_scope.policy_link",
  "family.consent_scope.full_policy_links",
  "family.consent_scope.update_required",
  "family.consent_scope.a11y.value.required",
  "family.consent_scope.a11y.value.agreed",
  "family.consent_scope.a11y.value.unavailable",
  "family.consent_scope.a11y.hint.core",
  "family.consent_scope.a11y.hint.unavailable",
  "family.consent_scope.a11y.action.policy",
  "family.consent_scope.manage_title",
  "family.consent_scope.manage_footer",
  "family.consent_scope.manage_pending",
  "family.consent_scope.manage_ended",
  "family.consent_scope.manage_none",
  "family.consent_scope.manage_unavailable",
  "family.child.consent_ack",
  "family.child.consent_ack_hint",
  "privacy.section12.intro.body",
  "privacy.section12.core.title",
  "privacy.section12.core.body",
  "privacy.section12.analytics.title",
  "privacy.section12.analytics.body",
  "privacy.section12.ads.title",
  "privacy.section12.ads.body",
  "privacy.section12.location.title",
  "privacy.section12.location.body",
  "privacy.section12.cross_family.title",
  "privacy.section12.cross_family.body",
];

/** Key families that are consent text by definition: a new key in one must join the list. */
const LOCKED_PREFIXES = [
  "family.consent_scope.",
  "privacy.section12.",
  "family.child.consent_ack",
] as const;

const here = dirname(fileURLToPath(import.meta.url));

function readStrings(locale: string): string {
  return readFileSync(
    join(here, `../../LicensePlateApp/${locale}.lproj/Localizable.strings`),
    "utf8"
  );
}

/** Same minimal `.strings` extractor as affirmationTextLock — handles \" \\ \n escapes. */
function extractLocalizedValue(contents: string, locale: string, key: string): string {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`"${escapedKey}"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*;`);
  const match = contents.match(pattern);
  if (!match) {
    throw new Error(
      `consentTextLock: could not find "${key}" in ${locale}.lproj/Localizable.strings. ` +
        "If the key was renamed or removed, update CONSENT_TEXT_KEYS here, bump " +
        "CONSENT_TEXT_VERSION and recompute CONSENT_TEXT_HASH in the same commit."
    );
  }
  return match[1].replace(/\\"/g, '"').replace(/\\n/g, "\n").replace(/\\\\/g, "\\");
}

function hashConsentText(): { hash: string; input: string } {
  const values = LOCALES.map((locale) => {
    const contents = readStrings(locale);
    return [
      locale,
      CONSENT_TEXT_KEYS.map((key) => [key, extractLocalizedValue(contents, locale, key)]),
    ];
  });
  const input = JSON.stringify(values);
  return { hash: createHash("sha256").update(input).digest("hex"), input };
}

describe("consent-text lock (F-21 / FR-103)", () => {
  it("CONSENT_TEXT_HASH matches the live en/es/fr consent text", () => {
    const { hash } = hashConsentText();
    if (hash !== CONSENT_TEXT_HASH) {
      throw new Error(
        "The app-shown consent text (CONSENT_TEXT_KEYS in en/es/fr Localizable.strings) no " +
          "longer matches CONSENT_TEXT_HASH in childAccountCore.ts. This text is consent " +
          "evidence: if you changed it on purpose, bump CONSENT_TEXT_VERSION (and the two " +
          "consentScopeCatalog.v1.json fixtures and Swift ConsentScopeCatalog.consentTextVersion " +
          "with it), then set CONSENT_TEXT_HASH to the hash below, all in the SAME commit. " +
          "After launch, a bump refuses older builds, so raise the force-update minimum too.\n" +
          `  newly computed hash: ${hash}\n` +
          `  recorded CONSENT_TEXT_HASH: ${CONSENT_TEXT_HASH}\n` +
          `  CONSENT_TEXT_VERSION: ${CONSENT_TEXT_VERSION}`
      );
    }
    expect(hash).toBe(CONSENT_TEXT_HASH);
  });

  it("the key list has no duplicates", () => {
    expect(new Set(CONSENT_TEXT_KEYS).size).toBe(CONSENT_TEXT_KEYS.length);
  });

  it("every consent-card and §12 key in every language is under the lock", () => {
    for (const locale of LOCALES) {
      const keys = [...readStrings(locale).matchAll(/^"([^"]+)"\s*=/gm)].map((m) => m[1]);
      const unlocked = keys.filter(
        (key) =>
          LOCKED_PREFIXES.some((prefix) => key.startsWith(prefix)) &&
          !CONSENT_TEXT_KEYS.includes(key)
      );
      expect(unlocked, `${locale}: consent keys missing from CONSENT_TEXT_KEYS`).toEqual([]);
    }
  });
});
