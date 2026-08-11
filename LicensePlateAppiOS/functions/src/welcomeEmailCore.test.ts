import { describe, expect, it } from "vitest";
import {
  applyWelcomeEmailSubjectLabel,
  buildWelcomeEmailContent,
  normalizeEmail,
  profileEmailChanged,
  redactEmailAddresses,
  shouldSuppressWelcomeEmailForChild,
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

describe("applyWelcomeEmailSubjectLabel", () => {
  const base = "Welcome to RoadTrip Royale!";

  it("leaves subject unchanged when label is empty", () => {
    expect(applyWelcomeEmailSubjectLabel(base)).toBe(base);
    expect(applyWelcomeEmailSubjectLabel(base, "")).toBe(base);
    expect(applyWelcomeEmailSubjectLabel(base, "   ")).toBe(base);
    expect(applyWelcomeEmailSubjectLabel(base, null)).toBe(base);
  });

  it("prefixes subject when label is set", () => {
    expect(applyWelcomeEmailSubjectLabel(base, "DEV")).toBe(`[DEV] ${base}`);
    expect(applyWelcomeEmailSubjectLabel(base, "  DEV  ")).toBe(`[DEV] ${base}`);
  });
});

describe("buildWelcomeEmailContent", () => {
  it("prefers first name in greeting", () => {
    const content = buildWelcomeEmailContent({
      firstName: "Alex",
      userName: "alex_r",
    });
    expect(content.greetingName).toBe("Alex");
    expect(content.subject).toBe("Welcome to RoadTrip Royale!");
    expect(content.html).toContain("Hi Alex,");
    expect(content.text).toContain("Hi Alex,");
  });

  it("adds env label only to the subject", () => {
    const content = buildWelcomeEmailContent({ firstName: "Alex" }, "DEV");
    expect(content.subject).toBe("[DEV] Welcome to RoadTrip Royale!");
    expect(content.html).not.toContain("[DEV]");
    expect(content.text).not.toContain("[DEV]");
  });

  it("falls back to username then generic greeting", () => {
    expect(buildWelcomeEmailContent({ userName: "alex_r" }).greetingName).toBe(
      "alex_r"
    );
    expect(buildWelcomeEmailContent({}).greetingName).toBe("there");
  });
});

describe("shouldSuppressWelcomeEmailForChild (COPPA FR-35c)", () => {
  it("suppresses only for an explicit isChildAccount true", () => {
    expect(shouldSuppressWelcomeEmailForChild({ isChildAccount: true })).toBe(true);
    expect(shouldSuppressWelcomeEmailForChild({ isChildAccount: false })).toBe(false);
    expect(shouldSuppressWelcomeEmailForChild({})).toBe(false);
    expect(shouldSuppressWelcomeEmailForChild(undefined)).toBe(false);
    expect(shouldSuppressWelcomeEmailForChild(null)).toBe(false);
    expect(shouldSuppressWelcomeEmailForChild({ isChildAccount: "true" })).toBe(false);
  });
});

describe("redactEmailAddresses (COPPA FR-35a)", () => {
  it("scrubs addresses out of provider error text", () => {
    expect(
      redactEmailAddresses(
        "Invalid recipient kid.name+tag@sub.example.co.uk (bounced); retry later"
      )
    ).toBe("Invalid recipient [redacted-email] (bounced); retry later");
  });

  it("handles multiple addresses and leaves plain text alone", () => {
    expect(
      redactEmailAddresses("from a@b.io to c@d.org")
    ).toBe("from [redacted-email] to [redacted-email]");
    expect(redactEmailAddresses("timeout after 30s")).toBe("timeout after 30s");
  });
});
