/**
 * FR-59/FR-59.1 email_plus — the consent-request lifecycle, end to end against the real
 * callables and the real confirmation transaction (§3.1.2 steps 1–3 + the expiry sweep).
 *
 * The properties a reviewer has to trust:
 *  1. APPROVE DOES NOT ADMIT. The captain's tap opens a guardian confirmation; no
 *     membership, no activeFamilyId, no consent record exists until the link is clicked.
 *  2. THE LINK IS SINGLE-USE AND HASHED. The stored document never holds a usable
 *     credential once the email is claimed; a wrong nonce is refused uniformly.
 *  3. FR-64 ATOMICITY. Consent record + guardianship + membership + activeFamilyId
 *     commit together — and REFUSE together when FR-110's marker is missing.
 *  4. THE DELETION TRAP IS CLOSED. An awaiting-guardian child is invisible to the FR-77
 *     sweep, and a second redemption dedupes against the awaiting row.
 *  5. EXPIRY IS REFUSAL BY SILENCE. The sweep retires the row, purges the guardian's
 *     email, and deletes the never-consented account inline.
 *  6. THE PLUS NOTICE COMPLETES THE METHOD. ≥24h after confirmation a second notice
 *     with the revocation path goes to the SAME address that confirmed — and only
 *     that send (or abandonment, or expiry) purges the address.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  deletedAuthUsers: [] as string[],
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
    increment: (n: number) => ({ __increment__: n }),
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  const auth: any = () => ({
    deleteUser: async (uid: string) => {
      holder.deletedAuthUsers.push(uid);
    },
  });
  const messaging: any = () => ({ send: async () => "sent" });
  return { default: { firestore, auth, messaging }, firestore, auth, messaging };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  commitGuardianConfirmation,
  reconcileConsentRecords,
  sendDueConsentPlusNotices,
  sweepExpiredConsentRequests,
  type ConfirmableRequest,
} from "./consentRequests";
import {
  CONSENT_PLUS_NOTICE_DELAY_MS,
  CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS,
  CONSENT_PLUS_NOTICE_OVERDUE_MS,
  CONSENT_REQUESTS_COLLECTION,
  CONSENT_REQUEST_TTL_MS,
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
  buildConsentPlusNoticeEmailContent,
  decideConsentConfirmation,
  hashConsentNonce,
  isPlusNoticeDue,
  isValidAgeOutYearMonth,
  parseConsentToken,
  resolvePlusNoticeDelayMillis,
} from "./consentRequestsCore";
import {
  confirmGuardianConsent,
  findLiveConsentRequest,
} from "./testSupport/consentTestHelpers";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const run = {
  createFamily: (uid: string, name: string) =>
    (createFamily as unknown as Runnable).run({ name }, context(uid)) as Promise<{
      familyId: string;
    }>,
  createShareCode: (uid: string, familyId: string) =>
    (createShareCode as unknown as Runnable).run(
      { type: "family", familyId },
      context(uid)
    ) as Promise<{ codeId: string; code: string }>,
  redeemShareCode: (uid: string, code: string) =>
    (redeemShareCode as unknown as Runnable).run(
      { code, expectedType: "family" },
      context(uid)
    ) as Promise<{ inviteId: string }>,
  acceptInvite: (uid: string, inviteId: string) =>
    (respondToFamilyInvite_UserStep as unknown as Runnable).run(
      { inviteId, response: "accept" },
      context(uid)
    ),
  approve: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "approve", ...payload },
      context(uid)
    ),
  decline: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "decline", ...payload },
      context(uid)
    ),
};

const CHILD_APPROVAL = {
  isChild: true,
  consentAcknowledged: true,
  guardianAffirmed: true,
};

async function childAwaiting(): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const { code } = await run.createShareCode("captain", familyId);
  const { inviteId } = await run.redeemShareCode("kid", code);
  await run.acceptInvite("kid", inviteId);
  const rows = [...db().store.entries()].filter(
    ([path, data]) =>
      path.startsWith(`families/${familyId}/pending/`) && data.status === "pending"
  );
  expect(rows).toHaveLength(1);
  const requestId = rows[0][0].split("/").pop()!;
  await run.approve("captain", { familyId, requestId, ...CHILD_APPROVAL });
  return { familyId, requestId };
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;

  db().seed("users/captain", { userName: "Captain" });
  db().seed("users/captain/private/contact", { email: "captain@example.com" });
  db().seed("users/kid", {
    userName: "Speedy",
    avatarId: "scout_otter",
    isChildAccount: true,
    childDeclaredAt: Date.now(),
    ageOutYearMonth: 203703,
  });
});

// ---------------------------------------------------------------------------
// 1. Approve opens a confirmation; it does not admit
// ---------------------------------------------------------------------------

describe("FR-59.1: approve creates the consent request and admits nobody", () => {
  it("row → awaiting_guardian; no membership, no activeFamilyId, no consent audit row", async () => {
    const { familyId, requestId } = await childAwaiting();

    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
    const consentRows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    );
    expect(consentRows).toHaveLength(0);
  });

  it("stores the nonce HASHED, with the raw copy only in the transient email field", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    const raw = found.data.pendingLinkNonce as string;
    const stored = found.data.nonceHash as string;
    expect(raw).toMatch(/^[a-f0-9]{32}$/);
    expect(stored).not.toBe(raw);
    expect(stored).toBe(hashConsentNonce(raw));
    // The guardian's email lives on the server-only doc, §312.5(c)(1).
    expect(found.data.guardianEmail).toBe("captain@example.com");
  });

  it("re-approve reuses the live request — one request, no second email nonce", async () => {
    const { familyId, requestId } = await childAwaiting();
    const first = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    await expect(
      run.approve("captain", { familyId, requestId, ...CHILD_APPROVAL })
    ).resolves.toMatchObject({ success: true, awaitingGuardianConfirmation: true });

    const requests = [...db().store.entries()].filter(([path]) =>
      path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)
    );
    expect(requests).toHaveLength(1);
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!.requestId).toBe(
      first.requestId
    );
  });

  it("a captain with no resolvable email is refused before any state changes", async () => {
    db().seed("users/captain2", { userName: "NoMail" });
    const { familyId } = await run.createFamily("captain2", "Mailless");
    const { code } = await run.createShareCode("captain2", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);
    const rows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith(`families/${familyId}/pending/`) && data.status === "pending"
    );
    const requestId = rows[0][0].split("/").pop()!;

    await expect(
      run.approve("captain2", { familyId, requestId, ...CHILD_APPROVAL })
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("pending");
  });
});

// ---------------------------------------------------------------------------
// 2. The confirmation transaction (FR-64) and its refusals
// ---------------------------------------------------------------------------

describe("FR-64: the guardian's click commits everything together", () => {
  it("membership + activeFamilyId + guardianship + level-1 consent record, one commit", async () => {
    const { familyId, requestId } = await childAwaiting();

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome.committed).toBe(true);

    expect(db().store.get(`families/${familyId}/members/kid`)?.isChild).toBe(true);
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(familyId);
    expect(db().store.get("users/kid")?.wasEverInFamily).toBe(true);
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("approved");

    // FR-62 groundwork: the durable guardianship record.
    expect(db().store.get("users/kid/private/guardianship")).toMatchObject({
      guardianUid: "captain",
      familyId,
      method: "email_plus",
      assuranceLevel: 1,
    });

    // The consent audit row, written INSIDE the transaction, carrying FR-108's level
    // and FR-110's marker.
    const consentRows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    );
    expect(consentRows).toHaveLength(1);
    expect(consentRows[0][1].metadata).toMatchObject({
      childUserId: "kid",
      method: "email_plus",
      assuranceLevel: 1,
      ageOutYearMonth: 203703,
      guardianAffirmed: true,
    });

    // §312.5(c)(1): the guardian's email SURVIVES confirmation — the method's ≥24h
    // plus notice must reach the same address that confirmed, so the purpose is not
    // served until that notice sends. The plus-notice suite pins the purge.
    const request = [...db().store.entries()].find(([path]) =>
      path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)
    )!;
    expect(request[1].status).toBe("confirmed");
    expect(request[1].guardianEmail).toBe("captain@example.com");
  });

  it("AGEOUT FR-110(b): a child doc without the marker refuses to commit — nothing admits", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      childDeclaredAt: Date.now(),
      // no ageOutYearMonth — the pre-F-14b install shape
    });
    const { familyId } = await childAwaiting();

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toMatchObject({ committed: false, reason: "missing_age_out_marker" });
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
  });

  it("a second click cannot double-admit: the request is no longer pending", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    expect((await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed).toBe(
      true
    );

    // Drive the raw commit again against the now-confirmed request.
    const data = found.data;
    const request: ConfirmableRequest = {
      familyId,
      childUserId: "kid",
      joinRequestId: data.joinRequestId as string,
      guardianUid: "captain",
      guardianRole: "creator",
      newRole: "scout",
      expectedAgeOutYearMonth: null,
      assuranceLevel: 1,
    };
    const again = await commitGuardianConfirmation(
      db() as never,
      db().collection(CONSENT_REQUESTS_COLLECTION).doc(found.requestId) as never,
      request,
      Date.now()
    );
    expect(again.committed).toBe(false);
  });

  it("a decline after approve cancels the request — the stale link refuses", async () => {
    const { familyId, requestId } = await childAwaiting();

    await run.decline("captain", { familyId, requestId });

    // The decline cancelled the consent request…
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })).toBeNull();
    // …so the guardian's link has nothing to confirm.
    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome.committed).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 3. The endpoint's pure gate
// ---------------------------------------------------------------------------

describe("the confirmation gate is uniform and single-use", () => {
  const base = {
    status: "pending",
    expiresAtMillis: 10_000,
    attempts: 0,
    nowMillis: 5_000,
    presentedNonce: "aa".repeat(16),
    storedNonceHash: hashConsentNonce("aa".repeat(16)),
  };

  it("confirms a live request with the right nonce, refuses a wrong one uniformly", () => {
    expect(decideConsentConfirmation(base)).toEqual({ kind: "confirm" });
    expect(
      decideConsentConfirmation({ ...base, presentedNonce: "bb".repeat(16) })
    ).toEqual({ kind: "refused" });
    // Superseded reads as plain refusal — the link is a bearer credential and state
    // oracles are FR-24's disease on a new surface.
    expect(decideConsentConfirmation({ ...base, status: "superseded" })).toEqual({
      kind: "refused",
    });
  });

  it("tells a CORRECT link the truth: already confirmed, or expired", () => {
    expect(decideConsentConfirmation({ ...base, status: "confirmed" })).toEqual({
      kind: "already_confirmed",
    });
    expect(decideConsentConfirmation({ ...base, nowMillis: 20_000 })).toEqual({
      kind: "expired",
    });
  });

  it("attempt exhaustion closes the request to brute force", () => {
    expect(decideConsentConfirmation({ ...base, attempts: 20 })).toEqual({
      kind: "refused",
    });
  });

  it("token parsing rejects malformed shapes outright", () => {
    expect(parseConsentToken("abc.def")).toBeNull(); // nonce not 32 hex
    expect(parseConsentToken(`abc.${"aa".repeat(16)}`)).toMatchObject({
      requestId: "abc",
    });
    expect(parseConsentToken(`.${"aa".repeat(16)}`)).toBeNull();
    expect(parseConsentToken("noseparator")).toBeNull();
    expect(parseConsentToken(42)).toBeNull();
    expect(parseConsentToken("x".repeat(300))).toBeNull();
  });

  it("marker validation bounds the plausible", () => {
    expect(isValidAgeOutYearMonth(203703)).toBe(true);
    expect(isValidAgeOutYearMonth(203700)).toBe(false); // month 0
    expect(isValidAgeOutYearMonth(203713)).toBe(false); // month 13
    expect(isValidAgeOutYearMonth(190001)).toBe(false); // year 1900 < floor
    expect(isValidAgeOutYearMonth("203703")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 4. The deletion trap and dedupe honor the awaiting state
// ---------------------------------------------------------------------------

describe("an awaiting-guardian child is live to every predicate", () => {
  it("the FR-77 sweep veto sees the awaiting row and leaves the account alone", async () => {
    const { familyId } = await childAwaiting();
    const { deleteProvisionalChildAccountIfNeverConsented } = await import(
      "./provisionalChildAccounts"
    );

    const result = await deleteProvisionalChildAccountIfNeverConsented(db() as never, {
      userId: "kid",
      actorId: "system_retention",
      clientMetadata: null,
      revenueCatApiKey: null,
    });
    expect(result).toMatchObject({ deleted: false, reason: "live_join_request" });
    expect(db().store.get("users/kid")).toBeDefined();
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })).not.toBeNull();
  });

  it("a re-redemption while awaiting does not reset the row or mint a rival", async () => {
    const { familyId, requestId } = await childAwaiting();
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);

    await expect(run.acceptInvite("kid", inviteId)).resolves.toMatchObject({
      success: true,
    });

    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    const rows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith(`families/${familyId}/pending/`) &&
        (data.status === "pending" ||
          data.status === JOIN_REQUEST_AWAITING_GUARDIAN_STATUS)
    );
    expect(rows).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// 5. Expiry — refusal by silence
// ---------------------------------------------------------------------------

describe("the expiry sweep closes a lapsed request per FR-60(c)", () => {
  it("request expired, email purged, row retired, account deleted inline", async () => {
    const { familyId, requestId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    const afterTtl =
      (found.data.requestedAtMillis as number) + CONSENT_REQUEST_TTL_MS + 1;
    const result = await sweepExpiredConsentRequests(db() as never, afterTtl);
    expect(result.expired).toBe(1);

    const request = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`)!;
    expect(request.status).toBe("expired");
    expect(request.guardianEmail).toBe("__delete__");
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("expired");
    // FR-60(c): consent not obtained within a reasonable time — deleted, Auth included.
    expect(db().store.get("users/kid")).toBeUndefined();
    expect(holder.deletedAuthUsers).toContain("kid");
  });

  it("leaves unexpired requests untouched", async () => {
    const { familyId, requestId } = await childAwaiting();

    const result = await sweepExpiredConsentRequests(db() as never, Date.now());
    expect(result.expired).toBe(0);
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    expect(db().store.get("users/kid")).toBeDefined();
  });

  it("a superseded request does not keep the guardian's address either", async () => {
    const { familyId, requestId } = await childAwaiting();
    const first = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    const firstPath = `${CONSENT_REQUESTS_COLLECTION}/${first.requestId}`;

    // Lapse the request without sweeping it, then re-approve: the stale doc must be
    // retired AND stripped of the address (it will never send another notice).
    db().store.set(firstPath, {
      ...db().store.get(firstPath)!,
      expiresAtMillis: Date.now() - 1,
    });
    await run.approve("captain", { familyId, requestId, ...CHILD_APPROVAL });

    const stale = db().store.get(firstPath)!;
    expect(stale.status).toBe("superseded");
    expect(stale.guardianEmail).toBe("__delete__");
    const fresh = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    expect(fresh.requestId).not.toBe(first.requestId);
  });
});

// ---------------------------------------------------------------------------
// 6. The ≥24h plus notice (§3.1.2 step 4)
// ---------------------------------------------------------------------------

describe("the plus notice completes the email_plus method", () => {
  async function confirmedRequest(): Promise<{
    path: string;
    confirmedAtMillis: number;
  }> {
    const { familyId } = await childAwaiting();
    expect(
      (await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed
    ).toBe(true);
    const entry = [...db().store.entries()].find(
      ([path, data]) =>
        path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`) && data.status === "confirmed"
    )!;
    return { path: entry[0], confirmedAtMillis: entry[1].confirmedAtMillis as number };
  }

  function passInput(nowMillis: number, sendEmail: ReturnType<typeof vi.fn>) {
    return {
      nowMillis,
      delayMillis: CONSENT_PLUS_NOTICE_DELAY_MS,
      envLabel: "",
      sendEmail: sendEmail as never,
    };
  }

  it("sends nothing before the delay elapses", async () => {
    const { confirmedAtMillis } = await confirmedRequest();
    const sendEmail = vi.fn(async () => ({ providerMessageId: "msg_1" }));

    const result = await sendDueConsentPlusNotices(
      db() as never,
      passInput(confirmedAtMillis + CONSENT_PLUS_NOTICE_DELAY_MS - 1, sendEmail)
    );

    expect(result).toEqual({ sent: 0, failed: 0, abandoned: 0 });
    expect(sendEmail).not.toHaveBeenCalled();
  });

  it("after the delay: notice to the CONFIRMING address, evidence stamped, address purged, never re-sent", async () => {
    const { path, confirmedAtMillis } = await confirmedRequest();
    const sendEmail = vi.fn(async () => ({ providerMessageId: "msg_1" }));
    const due = confirmedAtMillis + CONSENT_PLUS_NOTICE_DELAY_MS;

    const result = await sendDueConsentPlusNotices(db() as never, passInput(due, sendEmail));

    expect(result).toEqual({ sent: 1, failed: 0, abandoned: 0 });
    expect(sendEmail).toHaveBeenCalledTimes(1);
    const message = sendEmail.mock.calls[0][0] as Record<string, string>;
    // The retained address — NOT a re-resolution that could land in a different inbox.
    expect(message.to).toBe("captain@example.com");
    expect(message.subject).toContain("Speedy");
    expect(message.text).toContain("Family settings");

    const request = db().store.get(path)!;
    expect(request.status).toBe("confirmed"); // still "already confirmed" to a re-clicked link
    expect(request.plusNoticeSentAtMillis).toBe(due);
    expect(request.plusNoticeProviderMessageId).toBe("msg_1");
    expect(request.guardianEmail).toBe("__delete__"); // §312.5(c)(1) purpose now served

    const again = await sendDueConsentPlusNotices(
      db() as never,
      passInput(due + 60_000, sendEmail)
    );
    expect(again).toEqual({ sent: 0, failed: 0, abandoned: 0 });
    expect(sendEmail).toHaveBeenCalledTimes(1);
  });

  it("a pending (unconfirmed) request never gets a plus notice", async () => {
    await childAwaiting();
    const sendEmail = vi.fn(async () => ({ providerMessageId: "msg_1" }));

    const result = await sendDueConsentPlusNotices(
      db() as never,
      passInput(Date.now() + CONSENT_PLUS_NOTICE_DELAY_MS * 2, sendEmail)
    );

    expect(result).toEqual({ sent: 0, failed: 0, abandoned: 0 });
    expect(sendEmail).not.toHaveBeenCalled();
  });

  it("a request confirmed before the retained-email change falls back to the guardian's contact doc", async () => {
    // The pre-change shape: confirmed, address already purged at confirm time.
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/legacy1`, {
      familyId: "famX",
      childUserId: "kid",
      joinRequestId: "row1",
      guardianUid: "captain",
      status: "confirmed",
      confirmedAtMillis: 1_000,
      childUserName: "Speedy",
      noticeFamilyName: "Hammers",
    });
    const sendEmail = vi.fn(async () => ({ providerMessageId: "msg_legacy" }));

    const result = await sendDueConsentPlusNotices(
      db() as never,
      passInput(1_000 + CONSENT_PLUS_NOTICE_DELAY_MS, sendEmail)
    );

    expect(result).toEqual({ sent: 1, failed: 0, abandoned: 0 });
    // The harness auth mock has no getUser, so resolution fell through to
    // users/captain/private/contact — the production fallback order's second stop.
    expect((sendEmail.mock.calls[0][0] as Record<string, string>).to).toBe(
      "captain@example.com"
    );
    expect(
      db().store.get(`${CONSENT_REQUESTS_COLLECTION}/legacy1`)!.plusNoticeProviderMessageId
    ).toBe("msg_legacy");
  });

  it("a transient send failure keeps the address and retries on the next pass", async () => {
    const { path, confirmedAtMillis } = await confirmedRequest();
    const due = confirmedAtMillis + CONSENT_PLUS_NOTICE_DELAY_MS;
    const sendEmail = vi
      .fn()
      .mockRejectedValueOnce(new Error("resend 503"))
      .mockResolvedValue({ providerMessageId: "msg_2" });

    const first = await sendDueConsentPlusNotices(db() as never, passInput(due, sendEmail));
    expect(first).toEqual({ sent: 0, failed: 1, abandoned: 0 });
    const afterFailure = db().store.get(path)!;
    expect(afterFailure.plusNoticeAttempts).toBe(1);
    expect(afterFailure.plusNoticeLastFailedAtMillis).toBe(due);
    expect(afterFailure.guardianEmail).toBe("captain@example.com"); // kept, for the retry
    expect(afterFailure.plusNoticeSentAtMillis).toBeUndefined();

    const second = await sendDueConsentPlusNotices(
      db() as never,
      passInput(due + 900_000, sendEmail)
    );
    expect(second).toEqual({ sent: 1, failed: 0, abandoned: 0 });
    expect(db().store.get(path)!.guardianEmail).toBe("__delete__");
  });

  it("the attempt cap abandons loudly and purges the address anyway", async () => {
    const { path, confirmedAtMillis } = await confirmedRequest();
    const due = confirmedAtMillis + CONSENT_PLUS_NOTICE_DELAY_MS;
    db().store.set(path, {
      ...db().store.get(path)!,
      plusNoticeAttempts: CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS - 1,
    });
    const sendEmail = vi.fn().mockRejectedValue(new Error("hard bounce"));

    const result = await sendDueConsentPlusNotices(db() as never, passInput(due, sendEmail));

    expect(result).toEqual({ sent: 0, failed: 0, abandoned: 1 });
    const abandoned = db().store.get(path)!;
    expect(abandoned.plusNoticeAbandonedAtMillis).toBe(due);
    expect(abandoned.guardianEmail).toBe("__delete__"); // retention is bounded even in failure

    // Terminal: later passes skip it.
    const again = await sendDueConsentPlusNotices(
      db() as never,
      passInput(due + 900_000, sendEmail)
    );
    expect(again).toEqual({ sent: 0, failed: 0, abandoned: 0 });
    expect(sendEmail).toHaveBeenCalledTimes(1);
  });

  it("due-ness is pinned pure: status, stamp, and boundary semantics", () => {
    const base = { status: "confirmed", confirmedAtMillis: 1_000 };
    expect(isPlusNoticeDue(base, 1_000 + 100, 100)).toBe(true); // exactly at delay
    expect(isPlusNoticeDue(base, 1_000 + 99, 100)).toBe(false);
    expect(isPlusNoticeDue({ ...base, status: "pending" }, 999_999, 100)).toBe(false);
    expect(isPlusNoticeDue({ ...base, status: "expired" }, 999_999, 100)).toBe(false);
    expect(isPlusNoticeDue({ status: "confirmed" }, 999_999, 100)).toBe(false); // no timestamp
    expect(
      isPlusNoticeDue({ ...base, plusNoticeSentAtMillis: 2_000 }, 999_999, 100)
    ).toBe(false);
    expect(
      isPlusNoticeDue({ ...base, plusNoticeAbandonedAtMillis: 2_000 }, 999_999, 100)
    ).toBe(false);
  });

  it("the dev knob shortens the delay; anything invalid keeps the 24h floor", () => {
    expect(resolvePlusNoticeDelayMillis("")).toBe(CONSENT_PLUS_NOTICE_DELAY_MS);
    expect(resolvePlusNoticeDelayMillis("1")).toBe(60_000);
    expect(resolvePlusNoticeDelayMillis("90")).toBe(90 * 60_000);
    expect(resolvePlusNoticeDelayMillis("0")).toBe(CONSENT_PLUS_NOTICE_DELAY_MS);
    expect(resolvePlusNoticeDelayMillis("-30")).toBe(CONSENT_PLUS_NOTICE_DELAY_MS);
    expect(resolvePlusNoticeDelayMillis("abc")).toBe(CONSENT_PLUS_NOTICE_DELAY_MS);
  });

  it("the notice copy carries the revocation path and escapes what it interpolates", () => {
    const content = buildConsentPlusNoticeEmailContent({
      familyDisplayName: `<Fam&ly>`,
      childUserName: "Speedy",
      envLabel: "DEV",
    });
    expect(content.subject).toBe(
      "[DEV] Your consent for Speedy on RoadTrip Royale — and how to withdraw it"
    );
    expect(content.text).toContain("Family settings");
    expect(content.text).toContain("withdraw");
    expect(content.html).toContain("&lt;Fam&amp;ly&gt;");
    expect(content.html).not.toContain("<Fam&ly>");
  });
});

// ---------------------------------------------------------------------------
// 7. The nightly FR-64 reconcile (§3.1.2 step 8)
// ---------------------------------------------------------------------------

describe("the FR-64 reconcile re-derives the grant-time guarantee from stored state", () => {
  async function consentedKid(): Promise<{ familyId: string; requestPath: string }> {
    const { familyId } = await childAwaiting();
    expect(
      (await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed
    ).toBe(true);
    const entry = [...db().store.entries()].find(
      ([path, data]) =>
        path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`) && data.status === "confirmed"
    )!;
    return { familyId, requestPath: entry[0] };
  }

  it("a child consented through the real flow, plus notice sent, reconciles CLEAN", async () => {
    const { requestPath } = await consentedKid();
    db().store.set(requestPath, {
      ...db().store.get(requestPath)!,
      plusNoticeSentAtMillis: Date.now(),
    });

    const result = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });

    expect(result.consentedChildren).toBe(1);
    expect(result.missingRecord).toEqual([]);
    expect(result.belowRequiredLevel).toEqual([]);
    expect(result.plusNoticeAbandoned).toEqual([]);
    expect(result.plusNoticeOverdue).toEqual([]);
  });

  it("a consented child with NO grant row anywhere is a missing-record finding", async () => {
    db().seed("users/orphan", { isChildAccount: true, activeFamilyId: "famZ" });

    const result = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });

    expect(result.missingRecord).toEqual(["orphan"]);
    expect(result.belowRequiredLevel).toEqual([]);
  });

  it("a level-less legacy grant flags below-level; an email_plus row alongside it clears (max wins)", async () => {
    db().seed("users/legacyKid", { isChildAccount: true, activeFamilyId: "famZ" });
    db().seed("audit_logs/legacyGrant", {
      eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
      subjectId: "legacyKid",
      metadata: { method: "manager_set" }, // no assuranceLevel — the pre-email_plus shape
    });

    const flagged = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });
    expect(flagged.belowRequiredLevel).toEqual(["legacyKid"]);
    expect(flagged.missingRecord).toEqual([]);

    // The FR-28 sticky-readmission shape: original email_plus row + level-less
    // readmission row. The best row carries the child.
    db().seed("audit_logs/originalGrant", {
      eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
      subjectId: "legacyKid",
      metadata: { method: "email_plus", assuranceLevel: 1 },
    });
    const cleared = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });
    expect(cleared.belowRequiredLevel).toEqual([]);
  });

  it("adults and non-active children are out of scope", async () => {
    db().seed("users/adult", { activeFamilyId: "famZ" }); // no isChildAccount
    db().seed("users/stickyKid", { isChildAccount: true }); // no activeFamilyId (FR-28 post-revocation)

    const result = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });

    expect(result.consentedChildren).toBe(0);
    expect(result.missingRecord).toEqual([]);
  });

  it("an abandoned plus notice is a finding forever; an unsent one flags only once OVERDUE", async () => {
    const { requestPath } = await consentedKid();
    const requestId = requestPath.split("/").pop()!;
    const confirmedAtMillis = db().store.get(requestPath)!.confirmedAtMillis as number;

    // Fresh confirm, notice pending, well inside the window: not a finding.
    const early = await reconcileConsentRecords(db() as never, {
      nowMillis: confirmedAtMillis + CONSENT_PLUS_NOTICE_OVERDUE_MS - 1,
    });
    expect(early.plusNoticeOverdue).toEqual([]);
    expect(early.plusNoticeAbandoned).toEqual([]);

    // Same doc at the overdue boundary: the delivery job is broken — flag it.
    const late = await reconcileConsentRecords(db() as never, {
      nowMillis: confirmedAtMillis + CONSENT_PLUS_NOTICE_OVERDUE_MS,
    });
    expect(late.plusNoticeOverdue).toEqual([requestId]);

    // Abandonment is terminal and always a finding (and not double-counted as overdue).
    db().store.set(requestPath, {
      ...db().store.get(requestPath)!,
      plusNoticeAbandonedAtMillis: confirmedAtMillis + 1000,
    });
    const abandoned = await reconcileConsentRecords(db() as never, {
      nowMillis: confirmedAtMillis + CONSENT_PLUS_NOTICE_OVERDUE_MS * 2,
    });
    expect(abandoned.plusNoticeAbandoned).toEqual([requestId]);
    expect(abandoned.plusNoticeOverdue).toEqual([]);
  });
});
