import { createHash } from "crypto";
import { describe, expect, it } from "vitest";
import {
  CONSENT_NOTICE_TEXT_HASH,
  CONSENT_NOTICE_TEXT_VERSION,
  CONSENT_TEXT_HASH,
  CONSENT_TEXT_VERSION,
} from "./childAccountCore";
import { consentNoticeTextHashInput } from "./consentNoticeStrings";

/**
 * Consent-notice-text lock (F-21 versionBump, counter 2).
 *
 * CONSENT_NOTICE_TEXT_VERSION is stamped on every consent request at creation and copied
 * into the GRANTED row as the evidence of which server notice wording the guardian was
 * sent. It covers every string in `consentNoticeStrings.ts` (all languages): the scope
 * restatements in the request email, the pre-button page, the confirmed page and the plus
 * notice, the scope_selection_invalid failure page and the two rejection messages. This
 * test hashes that table and compares the hash with CONSENT_NOTICE_TEXT_HASH, so editing
 * any of it without bumping the version fails the suite.
 *
 * Unlike CONSENT_TEXT_VERSION, the client never sends or compares this version, so a bump
 * needs no app release and no force-update.
 */

describe("consent-notice-text lock (F-21)", () => {
  it("CONSENT_NOTICE_TEXT_HASH matches the live consentNoticeStrings table", () => {
    const hash = createHash("sha256").update(consentNoticeTextHashInput()).digest("hex");
    if (hash !== CONSENT_NOTICE_TEXT_HASH) {
      throw new Error(
        "The server consent notice text (consentNoticeStrings.ts) no longer matches " +
          "CONSENT_NOTICE_TEXT_HASH in childAccountCore.ts. This text is consent evidence: " +
          "if you changed it on purpose, bump CONSENT_NOTICE_TEXT_VERSION and set " +
          "CONSENT_NOTICE_TEXT_HASH to the hash below, in the SAME commit.\n" +
          `  newly computed hash: ${hash}\n` +
          `  recorded CONSENT_NOTICE_TEXT_HASH: ${CONSENT_NOTICE_TEXT_HASH}\n` +
          `  CONSENT_NOTICE_TEXT_VERSION: ${CONSENT_NOTICE_TEXT_VERSION}`
      );
    }
    expect(hash).toBe(CONSENT_NOTICE_TEXT_HASH);
  });

  it("pins the slice-3 notice version; the app consent-text counter is untouched", () => {
    // notice-v1 (slice 2) records carry the pre-restatement wording; v2 adds it.
    expect(CONSENT_NOTICE_TEXT_VERSION).toBe("2026-11-17.notice-v2");
    expect(CONSENT_TEXT_VERSION).toBe("2026-11-17.consent-scopes");
    expect(CONSENT_TEXT_HASH).toBe(
      "d40407aaf657e820a72f16c39cfeef4e2d200db1847838e3f856169a409a40a7"
    );
  });
});
