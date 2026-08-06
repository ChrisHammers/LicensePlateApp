/**
 * Parity: LicensePlateApp/Resources/ProgressionRewardsConfig.v1.json → xp.*
 */

export const XP_AMOUNTS = {
  baseDiscoveryXp: 10,
  firstFinderBonusXp: 5,
  lifetimeUniqueRegionFindBonusXp: 20,
  firstFindOfDayBonusXp: 10,
  competitiveFirstPlaceFinishBonusXp: 25,
  competitiveSecondPlaceFinishBonusXp: 10,
  competitiveThirdPlaceFinishBonusXp: 5,
  gameEndedBonusXp: 50,
  gameFullClearBonusXp: 200,
  tripEndedBonusXp: 100,
  tripParticipationBonusXp: 50,
  tripCompetitiveFirstPlaceBonusXp: 25,
} as const;

/** @deprecated Use XP_AMOUNTS.baseDiscoveryXp */
export const XP_PER_ACCEPTED_REGION_FOUND = XP_AMOUNTS.baseDiscoveryXp;
/** @deprecated Use XP_AMOUNTS.firstFinderBonusXp */
export const XP_PER_COMPETITIVE_FIRST_FINDER_BONUS = XP_AMOUNTS.firstFinderBonusXp;
/** @deprecated Use XP_AMOUNTS.competitiveFirstPlaceFinishBonusXp */
export const XP_PER_COMPETITIVE_FIRST_PLACE_FINISH = XP_AMOUNTS.competitiveFirstPlaceFinishBonusXp;
