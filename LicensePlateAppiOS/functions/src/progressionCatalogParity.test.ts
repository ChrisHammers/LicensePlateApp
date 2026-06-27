import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { describe, expect, it } from "vitest";

const here = dirname(fileURLToPath(import.meta.url));
const iosCatalogPath = join(here, "../../LicensePlateApp/Resources/ProgressionCatalog.v1.json");
const functionsCatalogPath = join(here, "progressionCatalog.v1.json");

describe("progressionCatalogParity", () => {
  it("iOS bundled catalog matches functions copy byte-for-byte", () => {
    const iosBytes = readFileSync(iosCatalogPath);
    const functionsBytes = readFileSync(functionsCatalogPath);
    expect(functionsBytes.equals(iosBytes)).toBe(true);
  });

  it("parsed catalogs are deep-equal", () => {
    const iosJson = JSON.parse(readFileSync(iosCatalogPath, "utf8"));
    const functionsJson = JSON.parse(readFileSync(functionsCatalogPath, "utf8"));
    expect(functionsJson).toEqual(iosJson);
  });
});
