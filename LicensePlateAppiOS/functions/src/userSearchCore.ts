import { parsePhoneNumberFromString } from "libphonenumber-js";
import { auditValueHash } from "./auditRedaction";

export type SearchMatchField = "username" | "email" | "phone";
export type SearchQueryKind = "email" | "phone" | "username";

export interface PublicSearchHit {
  userId: string;
  userName: string;
  displayName: string;
  avatarId: string | null;
  matchedField: SearchMatchField;
}

/** Missing `isRegistered` ⇒ registered (legacy). Explicit `false` ⇒ anonymous / not discoverable. */
export function isRegisteredForSearch(
  data: Record<string, unknown> | undefined | null
): boolean {
  if (!data) return false;
  return data.isRegistered !== false;
}

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

/** Default region US → E.164 like +12035551111. Returns null if unparseable. */
export function normalizePhoneE164(
  raw: string,
  defaultRegion: "US" = "US"
): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const parsed = parsePhoneNumberFromString(trimmed, defaultRegion);
  if (!parsed || !parsed.isValid()) return null;
  return parsed.format("E.164");
}

/** Safe Firestore doc id for an E.164 number (+ stored as prefix `p`). */
export function phoneLookupDocId(e164: string): string {
  if (e164.startsWith("+")) {
    return `p${e164.slice(1)}`;
  }
  return `p${e164}`;
}

export function normalizeUsernameLower(raw: string): string {
  return raw.trim().toLowerCase();
}

/**
 * Classify query for search modality.
 * Email if contains @; phone if mostly digits/punctuation and parses as E.164;
 * otherwise username. Failed phone parse falls through to username.
 */
export function classifySearchQuery(query: string): SearchQueryKind {
  const trimmed = query.trim();
  if (trimmed.includes("@")) {
    return "email";
  }

  const digitCount = (trimmed.match(/\d/g) || []).length;
  const nonPhoneNoise = trimmed.replace(/[\d\s\-+().]/g, "");
  const looksLikePhone =
    digitCount >= 7 && nonPhoneNoise.length === 0;

  if (looksLikePhone) {
    const e164 = normalizePhoneE164(trimmed);
    if (e164) return "phone";
  }

  return "username";
}

/** Matches AppUser.displayName on iOS. */
export function buildDisplayName(data: {
  userName?: string;
  firstName?: string | null;
  lastName?: string | null;
}): string {
  const first = (data.firstName || "").trim();
  const last = (data.lastName || "").trim();
  if (first && last) return `${first} ${last}`;
  if (first) return first;
  if (last) return last;
  return (data.userName || "").trim() || "User";
}

export function toPublicSearchHit(
  userId: string,
  data: Record<string, unknown>,
  matchedField: SearchMatchField
): PublicSearchHit | null {
  if (!isRegisteredForSearch(data)) return null;
  const userName =
    (typeof data.userName === "string" && data.userName) ||
    (typeof data.username === "string" && data.username) ||
    "";
  if (!userName) return null;

  const avatarId =
    typeof data.avatarId === "string" && data.avatarId.length > 0
      ? data.avatarId
      : null;

  return {
    userId,
    userName,
    displayName: buildDisplayName({
      userName,
      firstName: typeof data.firstName === "string" ? data.firstName : null,
      lastName: typeof data.lastName === "string" ? data.lastName : null,
    }),
    avatarId,
    matchedField,
  };
}

/**
 * Audit-safe stand-in for a search query: the modality plus a truncated SHA-256, never any
 * plaintext. Every modality is hashed — a username query is somebody's username, an email
 * domain identifies an employer or school, and last-4 digits narrow a phone number.
 */
export function auditQueryFingerprint(
  kind: SearchQueryKind,
  query: string
): string {
  return `${kind}:${auditValueHash(query) ?? "empty"}`;
}
