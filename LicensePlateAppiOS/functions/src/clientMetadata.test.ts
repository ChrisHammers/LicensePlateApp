import { describe, it, expect } from "vitest";
import { normalizeClientMetadata } from "./clientMetadata";

describe("normalizeClientMetadata", () => {
  it("whitelists expected client metadata fields", () => {
    expect(
      normalizeClientMetadata({
        phoneModel: " iPhone 15 Pro Max ",
        phoneModelIdentifier: " iPhone16,2 ",
        phoneOSVersion: " iOS 18.4 ",
        clientAppVersion: "1.2.3",
        clientAppBuild: "45",
        ignored: "nope",
      })
    ).toEqual({
      phoneModel: "iPhone 15 Pro Max",
      phoneModelIdentifier: "iPhone16,2",
      phoneOSVersion: "iOS 18.4",
      clientAppVersion: "1.2.3",
      clientAppBuild: "45",
    });
  });

  it("returns null when metadata is absent or empty", () => {
    expect(normalizeClientMetadata(undefined)).toBeNull();
    expect(normalizeClientMetadata({})).toBeNull();
    expect(normalizeClientMetadata({ phoneModel: " " })).toBeNull();
  });

  it("fills partially present metadata with unknown values", () => {
    expect(normalizeClientMetadata({ phoneModelIdentifier: "iPhone16,2" })).toEqual({
      phoneModel: "unknown",
      phoneModelIdentifier: "iPhone16,2",
      phoneOSVersion: "unknown",
      clientAppVersion: "unknown",
      clientAppBuild: "unknown",
    });
  });
});
