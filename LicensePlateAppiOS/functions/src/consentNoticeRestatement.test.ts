/**
 * F-21 slice 3: the request email, the plus notice and the pre-button page restate what
 * the guardian is agreeing to — the core line, then the scopes that are not available —
 * in the owner-approved deck's exact words, in both the text and the HTML part.
 *
 * The email and plus notice are built from the request's stored vector alone; the
 * pre-button page from the catalog alone. The endpoint, trigger and failure-page wiring
 * is pinned in consentRequests.test.ts.
 */

import { describe, expect, it } from "vitest";
import {
  buildConsentInterstitialPage,
  buildConsentPlusNoticeEmailContent,
  buildConsentRequestEmailContent,
  type ConsentRequestKind,
} from "./consentRequestsCore";
import { buildScopeVector, type ConsentScopeVector } from "./childAccountCore";
import {
  CONSENT_NOTICE_STRINGS,
  CONSENT_SCOPES_INVALID_MESSAGE,
  CONSENT_TEXT_OUTDATED_MESSAGE,
  formatConsentNoticeList,
} from "./consentNoticeStrings";
import { NOTICE_DECK } from "./testSupport/consentNoticeDeck";

const UNAVAILABLE_NAMES = [
  "usage analytics",
  "ads made for kids",
  "location shared with family",
  "being seen by other families",
] as const;

/** The same escaping the builders apply to every line they put in HTML. */
function html(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function requestEmail(kind: ConsentRequestKind, scopeVector: ConsentScopeVector) {
  return buildConsentRequestEmailContent({
    familyDisplayName: "Hammers",
    childUserName: "Speedy",
    confirmUrl: "https://example.test/confirm?t=x.y",
    envLabel: "",
    ttlHours: 72,
    kind,
    scopeVector,
  });
}

function plusNotice(kind: ConsentRequestKind, scopeVector: ConsentScopeVector) {
  return buildConsentPlusNoticeEmailContent({
    familyDisplayName: "Hammers",
    childUserName: "Speedy",
    envLabel: "",
    kind,
    scopeVector,
  });
}

function expectAllFourUnavailable(content: { text: string; html: string }): void {
  for (const name of UNAVAILABLE_NAMES) {
    expect(content.text).toContain(name);
    expect(content.html).toContain(html(name));
  }
}

const LAUNCH = buildScopeVector(["core"]);

describe("consentNoticeStrings is the approved deck, verbatim", () => {
  const en = CONSENT_NOTICE_STRINGS.en;
  const list = formatConsentNoticeList([...UNAVAILABLE_NAMES], en.list);

  it.each([
    ["notice.request.scopes_heading", en.request.scopesHeading],
    ["notice.request.scope_core.join", en.request.scopeCore.join],
    ["notice.request.scope_core.member_flag", en.request.scopeCore.memberFlag],
    ["notice.scopes_unavailable", `${en.scopesUnavailable.prefix}${list}${en.scopesUnavailable.suffix}`],
    ["notice.interstitial.scopes_heading", en.interstitial.scopesHeading],
    ["notice.interstitial.scope_core", en.interstitial.scopeCore],
    ["notice.plus.scopes_heading", en.plus.scopesHeading],
    ["notice.plus.scope_core.join", en.plus.scopeCore.join],
    ["notice.plus.scope_core.member_flag", en.plus.scopeCore.memberFlag],
    [
      "notice.plus.scopes_unavailable",
      `${en.plus.scopesUnavailable.prefix}${list}${en.plus.scopesUnavailable.suffix}`,
    ],
    ["notice.confirmed.title", en.confirmed.title],
    ["notice.confirmed.body.join", en.confirmed.body.join],
    ["notice.confirmed.body.member_flag", en.confirmed.body.memberFlag],
    ["notice.failure.scope_selection_invalid.title", en.failure.scopeSelectionInvalid.title],
    ["notice.failure.scope_selection_invalid.body", en.failure.scopeSelectionInvalid.body],
    ["notice.reject.consent_text_outdated", CONSENT_TEXT_OUTDATED_MESSAGE],
    ["notice.reject.consent_scopes_invalid", CONSENT_SCOPES_INVALID_MESSAGE],
  ] as const)("%s", (key, rendered) => {
    expect(rendered).toBe(NOTICE_DECK[key]);
  });

  it("keeps the any-captain wording of who would be asked first", () => {
    expect(NOTICE_DECK["notice.scopes_unavailable"]).toContain(
      "a parent or guardian who is a captain of your family"
    );
  });

  it("list grammar: one, two, and three-or-more items", () => {
    expect(formatConsentNoticeList([], en.list)).toBe("");
    expect(formatConsentNoticeList(["a"], en.list)).toBe("a");
    expect(formatConsentNoticeList(["a", "b"], en.list)).toBe("a and b");
    expect(formatConsentNoticeList(["a", "b", "c"], en.list)).toBe("a, b, and c");
  });
});

describe("the consent request email restates the stored vector (both kinds)", () => {
  it.each([
    ["join_admission", "notice.request.scope_core.join"],
    ["member_flag", "notice.request.scope_core.member_flag"],
  ] as const)("%s: heading, core line and all four unavailable scopes, text and HTML", (kind, coreKey) => {
    const content = requestEmail(kind, LAUNCH);
    for (const key of ["notice.request.scopes_heading", coreKey, "notice.scopes_unavailable"] as const) {
      expect(content.text).toContain(NOTICE_DECK[key]);
      expect(content.html).toContain(html(NOTICE_DECK[key]));
    }
    expectAllFourUnavailable(content);
    // The old collection paragraph is gone; the kept lines stay.
    expect(content.text).not.toContain("What we collect if you consent");
    expect(content.text).toContain(
      "We do not collect their real name, photos, contact information, or precise location, and there is no chat or messaging."
    );
    expect(content.text).toContain("How it is used:");
    // Text order: heading, core, then not-available.
    const heading = content.text.indexOf(NOTICE_DECK["notice.request.scopes_heading"]);
    const core = content.text.indexOf(NOTICE_DECK[coreKey]);
    const unavailable = content.text.indexOf(NOTICE_DECK["notice.scopes_unavailable"]);
    expect(heading).toBeGreaterThan(-1);
    expect(core).toBeGreaterThan(heading);
    expect(unavailable).toBeGreaterThan(core);
  });

  it("each kind carries only its own core line", () => {
    expect(requestEmail("join_admission", LAUNCH).text).not.toContain(
      NOTICE_DECK["notice.request.scope_core.member_flag"]
    );
    expect(requestEmail("member_flag", LAUNCH).text).not.toContain(
      NOTICE_DECK["notice.request.scope_core.join"]
    );
  });

  it("is built from the vector alone: no core line unless granted, and only the unavailable scopes listed, in catalog order", () => {
    const vector = buildScopeVector(["core"]);
    vector.core.state = "declined";
    vector.analytics_internal.state = "declined";
    vector.location_family_shared.state = "declined";
    const content = requestEmail("join_admission", vector);
    expect(content.text).not.toContain("Family play:");
    expect(content.text).toContain(
      "Not available yet (off for every child, nothing collected): ads made for kids and being seen by other families. If we ever offer one of these"
    );
    expect(content.text).not.toContain("usage analytics");
    expect(content.text).not.toContain("location shared with family");
  });
});

describe("the plus notice restates what was agreed (both kinds)", () => {
  it.each([
    ["join_admission", "notice.plus.scope_core.join"],
    ["member_flag", "notice.plus.scope_core.member_flag"],
  ] as const)("%s: heading, core line and the nothing-else line, text and HTML", (kind, coreKey) => {
    const content = plusNotice(kind, LAUNCH);
    for (const key of ["notice.plus.scopes_heading", coreKey, "notice.plus.scopes_unavailable"] as const) {
      expect(content.text).toContain(NOTICE_DECK[key]);
      expect(content.html).toContain(html(NOTICE_DECK[key]));
    }
    expectAllFourUnavailable(content);
    expect(content.text).not.toContain("What you consented to");
    // The withdrawal paragraphs are unchanged.
    expect(content.text).toContain(
      "To withdraw consent at any time: open RoadTrip Royale and go to Family settings."
    );
  });

  it("each kind carries only its own core line", () => {
    expect(plusNotice("join_admission", LAUNCH).text).not.toContain(
      NOTICE_DECK["notice.plus.scope_core.member_flag"]
    );
    expect(plusNotice("member_flag", LAUNCH).text).not.toContain(
      NOTICE_DECK["notice.plus.scope_core.join"]
    );
  });
});

describe("the pre-button page restates the terms from the catalog", () => {
  it("'By confirming, you agree to:', the kind-neutral core line and all four unavailable scopes, before the button", () => {
    const page = buildConsentInterstitialPage({ token: `abc123.${"ab".repeat(16)}`, envLabel: "" });
    for (const key of [
      "notice.interstitial.scopes_heading",
      "notice.interstitial.scope_core",
      "notice.scopes_unavailable",
    ] as const) {
      expect(page).toContain(html(NOTICE_DECK[key]));
      expect(page.indexOf(html(NOTICE_DECK[key]))).toBeLessThan(page.indexOf("<form"));
    }
    for (const name of UNAVAILABLE_NAMES) expect(page).toContain(html(name));
  });
});
