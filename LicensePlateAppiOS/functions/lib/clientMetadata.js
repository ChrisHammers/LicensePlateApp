"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeClientMetadata = normalizeClientMetadata;
exports.clientMetadataWrite = clientMetadataWrite;
const MAX_METADATA_VALUE_LENGTH = 128;
function cleanString(value) {
    if (typeof value !== "string")
        return null;
    const trimmed = value.trim();
    if (!trimmed)
        return null;
    return trimmed.slice(0, MAX_METADATA_VALUE_LENGTH);
}
function normalizeClientMetadata(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return null;
    }
    const input = value;
    const phoneModel = cleanString(input.phoneModel);
    const phoneModelIdentifier = cleanString(input.phoneModelIdentifier);
    const phoneOSVersion = cleanString(input.phoneOSVersion);
    const clientAppVersion = cleanString(input.clientAppVersion);
    const clientAppBuild = cleanString(input.clientAppBuild);
    if (!phoneModel && !phoneModelIdentifier && !phoneOSVersion && !clientAppVersion && !clientAppBuild) {
        return null;
    }
    return {
        phoneModel: phoneModel !== null && phoneModel !== void 0 ? phoneModel : "unknown",
        phoneModelIdentifier: phoneModelIdentifier !== null && phoneModelIdentifier !== void 0 ? phoneModelIdentifier : "unknown",
        phoneOSVersion: phoneOSVersion !== null && phoneOSVersion !== void 0 ? phoneOSVersion : "unknown",
        clientAppVersion: clientAppVersion !== null && clientAppVersion !== void 0 ? clientAppVersion : "unknown",
        clientAppBuild: clientAppBuild !== null && clientAppBuild !== void 0 ? clientAppBuild : "unknown",
    };
}
function clientMetadataWrite(clientMetadata) {
    return clientMetadata ? { clientMetadata } : {};
}
//# sourceMappingURL=clientMetadata.js.map