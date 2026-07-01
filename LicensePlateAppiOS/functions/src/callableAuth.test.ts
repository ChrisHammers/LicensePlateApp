import { describe, it, expect } from "vitest";
import * as functions from "firebase-functions";
import {
  assertAuthenticated,
  assertRegisteredAccount,
} from "./callableAuth";

function makeContext(
  auth: functions.https.CallableContext["auth"]
): functions.https.CallableContext {
  return { auth } as functions.https.CallableContext;
}

describe("callableAuth", () => {
  it("assertAuthenticated rejects missing auth", () => {
    expect(() => assertAuthenticated(makeContext(undefined))).toThrowError(
      /authenticated/i
    );
  });

  it("assertAuthenticated returns uid for signed-in users", () => {
    expect(
      assertAuthenticated(
        makeContext({
          uid: "user-123",
          token: { firebase: { sign_in_provider: "password" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toBe("user-123");
  });

  it("assertRegisteredAccount rejects anonymous Firebase accounts", () => {
    expect(() =>
      assertRegisteredAccount(
        makeContext({
          uid: "anon-123",
          token: { firebase: { sign_in_provider: "anonymous" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toThrowError(/registered account/i);
  });

  it("assertRegisteredAccount allows linked OAuth accounts", () => {
    expect(
      assertRegisteredAccount(
        makeContext({
          uid: "signed-123",
          token: { firebase: { sign_in_provider: "google.com" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toBe("signed-123");
  });
});
