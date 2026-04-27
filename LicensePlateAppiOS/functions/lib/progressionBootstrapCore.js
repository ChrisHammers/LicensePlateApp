"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildProgressionBootstrapDefaults = buildProgressionBootstrapDefaults;
function buildProgressionBootstrapDefaults(existingData) {
    const data = existingData !== null && existingData !== void 0 ? existingData : {};
    const defaults = {};
    if (data.schemaVersion == null)
        defaults.schemaVersion = 1;
    if (data.totalXp == null)
        defaults.totalXp = 0;
    if (data.acceptedRegionFindCount == null)
        defaults.acceptedRegionFindCount = 0;
    if (data.competitiveFirstPlaceFinishes == null)
        defaults.competitiveFirstPlaceFinishes = 0;
    if (data.everCompetitiveFirstPlace == null)
        defaults.everCompetitiveFirstPlace = false;
    if (data.appliedProgressionEvents == null)
        defaults.appliedProgressionEvents = {};
    if (data.appliedProgressionScopes == null)
        defaults.appliedProgressionScopes = {};
    return defaults;
}
//# sourceMappingURL=progressionBootstrapCore.js.map