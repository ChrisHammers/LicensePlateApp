export const FOUNDER_TAG = "founder";

export type FounderProgramConfig = {
  enabled: boolean;
  endsAt: Date | null;
};

export type FounderGrantDecision =
  | { outcome: "grant" }
  | { outcome: "alreadyGranted" }
  | { outcome: "programEnded" }
  | { outcome: "programDisabled" };

export function parseEntitlementTags(userData: Record<string, unknown> | undefined | null): string[] {
  const raw = userData?.entitlementTags;
  if (!Array.isArray(raw)) return [];
  return raw.filter((value): value is string => typeof value === "string" && value.length > 0);
}

export function hasFounderTag(userData: Record<string, unknown> | undefined | null): boolean {
  return parseEntitlementTags(userData).includes(FOUNDER_TAG);
}

export function parseFounderProgramConfig(
  data: Record<string, unknown> | undefined | null,
  now: Date = new Date()
): FounderProgramConfig {
  if (!data) {
    return { enabled: true, endsAt: null };
  }

  const enabled = data.enabled !== false;
  let endsAt: Date | null = null;

  const rawEndsAt = data.endsAt;
  if (rawEndsAt != null) {
    if (typeof rawEndsAt === "object" && rawEndsAt !== null && "toDate" in rawEndsAt) {
      const converted = (rawEndsAt as { toDate: () => Date }).toDate();
      if (!Number.isNaN(converted.getTime())) {
        endsAt = converted;
      }
    } else if (typeof rawEndsAt === "string" || typeof rawEndsAt === "number") {
      const converted = new Date(rawEndsAt);
      if (!Number.isNaN(converted.getTime())) {
        endsAt = converted;
      }
    }
  }

  void now;
  return { enabled, endsAt };
}

export function isFounderProgramActive(config: FounderProgramConfig, now: Date = new Date()): boolean {
  if (!config.enabled) return false;
  if (config.endsAt != null && config.endsAt.getTime() <= now.getTime()) return false;
  return true;
}

export function decideFounderGrant(params: {
  userData: Record<string, unknown> | undefined | null;
  programConfig: FounderProgramConfig;
  now?: Date;
}): FounderGrantDecision {
  const now = params.now ?? new Date();

  if (hasFounderTag(params.userData)) {
    return { outcome: "alreadyGranted" };
  }

  if (!params.programConfig.enabled) {
    return { outcome: "programDisabled" };
  }

  if (!isFounderProgramActive(params.programConfig, now)) {
    return { outcome: "programEnded" };
  }

  return { outcome: "grant" };
}
