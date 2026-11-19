/**
 * F-21 (FR-65 / FR-103): the server-shown consent notice text that restates what a
 * guardian agrees to — the request email's "What you are agreeing to" block, the
 * confirmation link's pre-button restatement, the confirmed page, the plus notice's
 * "What you agreed to" block, the scope_selection_invalid failure page — and the two
 * HttpsError messages the child-consent entry points refuse with.
 *
 * Every string is the owner-approved copy deck's English (`notice.*` keys), character
 * for character. The text sits under CONSENT_NOTICE_TEXT_VERSION (childAccountCore.ts):
 * `consentNoticeTextLock.test.ts` hashes `consentNoticeTextHashInput()` and compares it
 * with CONSENT_NOTICE_TEXT_HASH, so no string here can change without a version bump.
 *
 * Shape: one `ConsentNoticeStrings` table per language. English only for now; Spanish
 * and French join `CONSENT_NOTICE_STRINGS` beside `en` (and `ConsentNoticeLanguage`
 * widens) without any caller changing. Lists are composed from data, never code, so the
 * whole table stays hashable.
 */

import type { ConsentScopeId } from "./childAccountCore";

export type ConsentNoticeLanguage = "en";

/** A scope that can be listed as "not available": every catalog scope except core. */
export type ListableConsentScopeId = Exclude<ConsentScopeId, "core">;

/** Per-kind variants: a child joining (`join`) vs an existing member marked as a child. */
export interface ConsentNoticeKindVariants {
  join: string;
  memberFlag: string;
}

/** "A, B, C, and D" — the pieces of a language's list grammar. */
export interface ConsentNoticeListGrammar {
  /** Between two items when there are exactly two. */
  pairSeparator: string;
  /** Between items, except before the last of three or more. */
  separator: string;
  /** Before the last of three or more. */
  finalSeparator: string;
}

export interface ConsentNoticeStrings {
  list: ConsentNoticeListGrammar;
  /** How each scope is named inside the "not available" lists. */
  scopeListNames: Readonly<Record<ListableConsentScopeId, string>>;
  request: {
    /** notice.request.scopes_heading */
    scopesHeading: string;
    /** notice.request.scope_core.join / .member_flag */
    scopeCore: ConsentNoticeKindVariants;
  };
  /** notice.scopes_unavailable, split around the list of unavailable scopes. */
  scopesUnavailable: { prefix: string; suffix: string };
  interstitial: {
    /** notice.interstitial.scopes_heading */
    scopesHeading: string;
    /** notice.interstitial.scope_core (kind-neutral) */
    scopeCore: string;
  };
  plus: {
    /** notice.plus.scopes_heading */
    scopesHeading: string;
    /** notice.plus.scope_core.join / .member_flag */
    scopeCore: ConsentNoticeKindVariants;
    /** notice.plus.scopes_unavailable, split around the list of unavailable scopes. */
    scopesUnavailable: { prefix: string; suffix: string };
  };
  confirmed: {
    /** notice.confirmed.title */
    title: string;
    /** notice.confirmed.body.join / .member_flag */
    body: ConsentNoticeKindVariants;
  };
  failure: {
    /** notice.failure.scope_selection_invalid.title / .body */
    scopeSelectionInvalid: { title: string; body: string };
  };
  reject: {
    /** notice.reject.consent_text_outdated */
    consentTextOutdated: string;
    /** notice.reject.consent_scopes_invalid (the same text on purpose) */
    consentScopesInvalid: string;
  };
}

const EN: ConsentNoticeStrings = {
  list: { pairSeparator: " and ", separator: ", ", finalSeparator: ", and " },
  scopeListNames: {
    analytics_internal: "usage analytics",
    ads_child_directed: "ads made for kids",
    location_family_shared: "location shared with family",
    cross_family_visibility: "being seen by other families",
  },
  request: {
    scopesHeading: "What you are agreeing to",
    scopeCore: {
      join: "Family play: required to join a family. We save your child's nickname, cartoon avatar, game activity (plates found, scores, ranks, achievements, and the trips they join), the month and year they turn 13, and an account ID the app creates, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with your child (always family) see that trip. Notifications are about your family, your trips, and play reminders, never ads.",
      memberFlag:
        "Family play: required to stay in the family. We save this player's nickname, cartoon avatar, game activity (plates found, scores, ranks, achievements, and the trips they join), the month and year they turn 13, and an account ID the app creates, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them (always family) see that trip. Notifications are about your family, your trips, and play reminders, never ads.",
    },
  },
  scopesUnavailable: {
    prefix: "Not available yet (off for every child, nothing collected): ",
    suffix:
      ". If we ever offer one of these, a parent or guardian who is a captain of your family will be asked first.",
  },
  interstitial: {
    scopesHeading: "By confirming, you agree to:",
    scopeCore:
      "Family play: your child's nickname, cartoon avatar, game activity, the month and year they turn 13, an account ID, basic device details, crash reports, and a notification token if notifications are on are saved and shared with your family. Notifications are about your family, your trips, and play reminders, never ads. This is required for your child to play in your family.",
  },
  plus: {
    scopesHeading: "What you agreed to",
    scopeCore: {
      join: "Family play (required to join a family): we save this player's nickname, cartoon avatar, game activity, the month and year they turn 13, and an account ID, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them see that trip. Notifications are about your family, your trips, and play reminders.",
      memberFlag:
        "Family play (required to stay in the family): we save this player's nickname, cartoon avatar, game activity, the month and year they turn 13, and an account ID, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them see that trip. Notifications are about your family, your trips, and play reminders.",
    },
    scopesUnavailable: {
      prefix: "Nothing else is turned on: ",
      suffix: " are not available and are off.",
    },
  },
  confirmed: {
    title: "Consent confirmed",
    body: {
      join: "Thank you. The player's account is now active in your family. You agreed to Family play: their nickname, cartoon avatar, and game activity are saved and shown to your family, and notifications are about your family, your trips, and play reminders. Nothing else is turned on: usage analytics, ads made for kids, location shared with family, and being seen by other families are not available. You can review this, or withdraw consent, at any time from Family settings in the RoadTrip Royale app.",
      memberFlag:
        "Thank you. Their account stays active in your family. You agreed to Family play: their nickname, cartoon avatar, and game activity are saved and shown to your family, and notifications are about your family, your trips, and play reminders. Nothing else is turned on: usage analytics, ads made for kids, location shared with family, and being seen by other families are not available. You can review this, or withdraw consent, at any time from Family settings in the RoadTrip Royale app.",
    },
  },
  failure: {
    scopeSelectionInvalid: {
      title: "This link can't be completed",
      body: "What this link asked you to agree to has changed, so it can't go through, and trying again won't help. Open RoadTrip Royale and approve the request again; you'll get a fresh email.",
    },
  },
  reject: {
    consentTextOutdated:
      "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.",
    consentScopesInvalid:
      "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.",
  },
};

export const CONSENT_NOTICE_STRINGS: Readonly<Record<ConsentNoticeLanguage, ConsentNoticeStrings>> = {
  en: EN,
};

export function consentNoticeStrings(language: ConsentNoticeLanguage = "en"): ConsentNoticeStrings {
  return CONSENT_NOTICE_STRINGS[language];
}

/** Joins list items with a language's grammar: "A", "A and B", "A, B, and C". */
export function formatConsentNoticeList(
  items: readonly string[],
  grammar: ConsentNoticeListGrammar
): string {
  if (items.length <= 1) return items.join("");
  if (items.length === 2) return `${items[0]}${grammar.pairSeparator}${items[1]}`;
  return `${items.slice(0, -1).join(grammar.separator)}${grammar.finalSeparator}${items[items.length - 1]}`;
}

/**
 * The HttpsError messages both child-consent entry points refuse with
 * (childAccountCore `checkConsentCapture`). Builds without the details.reason mapping
 * show the raw message, so it reads as an instruction to the captain. English: the
 * callable does not know the captain's language yet.
 */
export const CONSENT_TEXT_OUTDATED_MESSAGE = EN.reject.consentTextOutdated;
export const CONSENT_SCOPES_INVALID_MESSAGE = EN.reject.consentScopesInvalid;

/** The exact input CONSENT_NOTICE_TEXT_HASH is the SHA-256 hex digest of. */
export function consentNoticeTextHashInput(): string {
  return JSON.stringify(CONSENT_NOTICE_STRINGS);
}
