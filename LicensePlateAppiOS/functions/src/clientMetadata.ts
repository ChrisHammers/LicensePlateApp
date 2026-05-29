export interface ClientMetadata {
  phoneModel: string;
  phoneModelIdentifier: string;
  phoneOSVersion: string;
  clientAppVersion: string;
  clientAppBuild: string;
}

const MAX_METADATA_VALUE_LENGTH = 128;

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, MAX_METADATA_VALUE_LENGTH);
}

export function normalizeClientMetadata(value: unknown): ClientMetadata | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const input = value as Record<string, unknown>;
  const phoneModel = cleanString(input.phoneModel);
  const phoneModelIdentifier = cleanString(input.phoneModelIdentifier);
  const phoneOSVersion = cleanString(input.phoneOSVersion);
  const clientAppVersion = cleanString(input.clientAppVersion);
  const clientAppBuild = cleanString(input.clientAppBuild);

  if (!phoneModel && !phoneModelIdentifier && !phoneOSVersion && !clientAppVersion && !clientAppBuild) {
    return null;
  }

  return {
    phoneModel: phoneModel ?? "unknown",
    phoneModelIdentifier: phoneModelIdentifier ?? "unknown",
    phoneOSVersion: phoneOSVersion ?? "unknown",
    clientAppVersion: clientAppVersion ?? "unknown",
    clientAppBuild: clientAppBuild ?? "unknown",
  };
}

export function clientMetadataWrite(clientMetadata: ClientMetadata | null): { clientMetadata?: ClientMetadata } {
  return clientMetadata ? { clientMetadata } : {};
}
