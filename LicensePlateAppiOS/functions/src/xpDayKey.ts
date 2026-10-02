/**
 * The XP day key — `yyyy-MM-dd`, stamped by the DEVICE.
 *
 * Owner principle OD-16: the client is assumed correct and the server reconciles to the
 * device's decision, including the device's DAY. `first_find_of_day` is scoped on this key,
 * so whoever resolves it must use the same value the device used — a server-clock UTC day
 * is a different day for every evening find west of Greenwich.
 *
 * Lives in its own module because BOTH `gameplayEventResolver` (which authors payloads) and
 * `progressionCore` (which reads them) need it, and `progressionCore` already imports from
 * `gameplayEventResolver` — a helper in either of those two would be an import cycle.
 */

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** The key as given when it is well-formed `yyyy-MM-dd`; `null` for absent or malformed. */
export function normalizeXpDayKey(raw: string | undefined | null): string | null {
  if (!raw || !DAY_KEY_RE.test(raw)) return null;
  return raw;
}

/** The UTC day of a unix instant. The fallback when no device day is available. */
export function utcDayKeyFromUnixSeconds(seconds: number): string {
  const d = new Date(Math.floor(seconds) * 1000);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}
