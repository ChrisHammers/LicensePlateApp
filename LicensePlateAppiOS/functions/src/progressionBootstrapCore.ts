export interface ProgressionBootstrapDefaults {
  schemaVersion?: number;
  totalXp?: number;
  acceptedRegionFindCount?: number;
  competitiveFirstPlaceFinishes?: number;
  everCompetitiveFirstPlace?: boolean;
  appliedProgressionEvents?: Record<string, unknown>;
  appliedProgressionScopes?: Record<string, unknown>;
}

export function buildProgressionBootstrapDefaults(
  existingData: Record<string, unknown> | undefined | null
): ProgressionBootstrapDefaults {
  const data = existingData ?? {};
  const defaults: ProgressionBootstrapDefaults = {};

  if (data.schemaVersion == null) defaults.schemaVersion = 1;
  if (data.totalXp == null) defaults.totalXp = 0;
  if (data.acceptedRegionFindCount == null) defaults.acceptedRegionFindCount = 0;
  if (data.competitiveFirstPlaceFinishes == null) defaults.competitiveFirstPlaceFinishes = 0;
  if (data.everCompetitiveFirstPlace == null) defaults.everCompetitiveFirstPlace = false;
  if (data.appliedProgressionEvents == null) defaults.appliedProgressionEvents = {};
  if (data.appliedProgressionScopes == null) defaults.appliedProgressionScopes = {};

  return defaults;
}
