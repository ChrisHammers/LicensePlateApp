import { describe, expect, it } from "vitest";
import {
  buildWelcomeEmailContent,
  normalizeEmail,
  profileEmailChanged,
} from "./welcomeEmailCore";

describe("normalizeEmail", () => {
  it("normalizes valid emails", () => {
    expect(normalizeEmail(" Player@Example.com ")).toBe("player@example.com");
  });

  it("rejects invalid values", () => {
    expect(normalizeEmail(undefined)).toBeNull();
    expect(normalizeEmail("not-an-email")).toBeNull();
    expect(normalizeEmail("   ")).toBeNull();
  });
});

describe("profileEmailChanged", () => {
  it("returns true when email is first set", () => {
    expect(
      profileEmailChanged(null, { email: "player@example.com" })
    ).toBe(true);
  });

  it("returns false when email is unchanged", () => {
    expect(
      profileEmailChanged(
        { email: "player@example.com" },
        { email: "Player@Example.com" }
      )
    ).toBe(false);
  });

  it("returns true when email changes", () => {
    expect(
      profileEmailChanged(
        { email: "old@example.com" },
        { email: "new@example.com" }
      )
    ).toBe(true);
  });
});

describe("buildWelcomeEmailContent", () => {
  it("prefers first name in greeting", () => {
    const content = buildWelcomeEmailContent({
      firstName: "Alex",
      userName: "alex_r",
    });
    expect(content.greetingName).toBe("Alex");
    expect(content.subject).toContain("RoadTrip Royale");
    expect(content.html).toContain("Hi Alex,");
    expect(content.text).toContain("Hi Alex,");
  });

  it("falls back to username then generic greeting", () => {
    expect(buildWelcomeEmailContent({ userName: "alex_r" }).greetingName).toBe(
      "alex_r"
    );
    expect(buildWelcomeEmailContent({}).greetingName).toBe("there");
  });
});
