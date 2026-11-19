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
  sentPushes: [] as Array<Record<string, any>>,
  sentEmails: [] as Array<Record<string, any>>,
}));

// The onCreate trigger's provider call: captured, never sent.
vi.mock("./utils/email", () => ({
  sendTransactionalEmail: async (params: Record<string, any>) => {
    holder.sentEmails.push(params);
    return { providerMessageId: "msg_test" };
  },
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
  const messaging: any = () => ({
    send: async (message: Record<string, any>) => {
      holder.sentPushes.push(message);
      return "sent";
    },
  });
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
  claimConsentRequestEmail,
  commitGuardianConfirmation,
  consentRequestEvidenceMatches,
  createConsentRequestForApproval,
  createMemberFlagConsentRequest,
  confirmationFailurePage,
  confirmParentalConsent,
  consentConfirmedPage,
  onConsentRequestCreatedSendEmail,
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
  buildConsentInterstitialPage,
  buildConsentPlusNoticeEmailContent,
  buildConsentRequestEmailContent,
  consentEndpointAction,
  decideConsentConfirmation,
  escapeHtml,
  formatConsentToken,
  hashConsentNonce,
  isPlusNoticeDue,
  isValidAgeOutYearMonth,
  parseConsentToken,
  resolvePlusNoticeDelayMillis,
} from "./consentRequestsCore";
import { NOTICE_DECK } from "./testSupport/consentNoticeDeck";
import {
  confirmGuardianConsent,
  findLiveConsentRequest,
  LAUNCH_CONSENT_PAYLOAD,
} from "./testSupport/consentTestHelpers";
import {
  CONSENT_NOTICE_TEXT_VERSION,
  CONSENT_POLICY_VERSIONS,
  CONSENT_TEXT_VERSION,
  buildScopeVector,
} from "./childAccountCore";

/** The evidence a slice-2 request carries (F-21), as stored at creation. */
function launchEvidence(): Record<string, unknown> {
  return {
    scopeVector: buildScopeVector(["core"]),
    consentTextVersion: CONSENT_TEXT_VERSION,
    noticeTextVersion: CONSENT_NOTICE_TEXT_VERSION,
    policyVersions: { ...CONSENT_POLICY_VERSIONS },
  };
}

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
  ...LAUNCH_CONSENT_PAYLOAD,
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
  holder.sentPushes.length = 0;
  holder.sentEmails.length = 0;

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

  it("confirmation notifies the GUARDIAN's device — the admission happened out-of-band", async () => {
    // Owner device pass 2026-08-27: the click happens in a mail client, so no callable
    // return refreshes the captain UI. The push is the refresh trigger.
    db().seed("users/captain/private/fcm", { token: "captain-device-token" });
    const { familyId } = await childAwaiting();

    expect(
      (await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed
    ).toBe(true);

    const guardianPushes = holder.sentPushes.filter(
      (m) => m.data?.type === "family_consent_confirmed"
    );
    expect(guardianPushes).toHaveLength(1);
    expect(guardianPushes[0].token).toBe("captain-device-token");
    expect(guardianPushes[0].data.familyId).toBe(familyId);
    expect(guardianPushes[0].data.deepLink).toBe(`roadtrip-royale://family/${familyId}`);
    // Name-free by design: the child's username stays off the push channel.
    expect(JSON.stringify(guardianPushes[0])).not.toContain("Speedy");
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

  // The remaining `committed: false` reasons (2026-09-07 audit, alongside the confirmation
  // page copy fix): each is reached only once the request itself is still `pending` (the
  // endpoint's own gate already required that), so every one of these describes a state that
  // changed OUT from under an otherwise-live link — never something a retry can fix.

  it("child_gone: the child's account was deleted between approval and the guardian's click", async () => {
    const { familyId } = await childAwaiting();
    db().store.delete("users/kid");

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toMatchObject({ committed: false, reason: "child_gone" });
  });

  it("other_family: the child joined a different family before this guardian confirmed", async () => {
    const { familyId } = await childAwaiting();
    db().store.set("users/kid", {
      ...db().store.get("users/kid")!,
      activeFamilyId: "some-other-family",
    });

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toMatchObject({ committed: false, reason: "other_family" });
  });

  it("row_gone: the underlying join request was cancelled while confirmation was outstanding", async () => {
    const { familyId, requestId } = await childAwaiting();
    const rowPath = `families/${familyId}/pending/${requestId}`;
    db().store.set(rowPath, { ...db().store.get(rowPath)!, status: "declined" });

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toMatchObject({ committed: false, reason: "row_gone" });
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
    // This reason is the one race commitGuardianConfirmation can still hit after the
    // endpoint's own pending-status gate: a concurrent commit on the SAME link already won.
    expect(again).toMatchObject({ committed: false, reason: "request_not_pending" });
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
// 2b. The endpoint renders the reason-specific copy for a real refusal
// ---------------------------------------------------------------------------

describe("confirmParentalConsent renders truthful, reason-specific copy on refusal", () => {
  function fakeResponse(): {
    res: { status: (code: number) => unknown; send: (body: string) => unknown; set: (key: string, value: string) => unknown };
    calls: { statusCode?: number; body?: string };
  } {
    const calls: { statusCode?: number; body?: string } = {};
    const res = {
      set: () => res,
      status(code: number) {
        calls.statusCode = code;
        return res;
      },
      send(body: string) {
        calls.body = body;
        return res;
      },
    };
    return { res, calls };
  }

  it("missing_age_out_marker: 409 with the reinstall-and-rejoin copy, never the generic 'try again' line", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      childDeclaredAt: Date.now(),
      // no ageOutYearMonth — the pre-F-14b install shape
    });
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    const rawNonce = found.data.pendingLinkNonce as string;
    // FakeFirestore's auto-ids look like "auto_0007" — the underscore fails
    // `parseConsentToken`'s requestId shape, which is deliberately as strict as a REAL
    // Firestore auto-id (alphanumeric only, never underscored). Move the seeded request to
    // a clean id so the token this test builds is shape-valid, exactly like a real one.
    const requestId = "req1";
    db().store.set(
      `${CONSENT_REQUESTS_COLLECTION}/${requestId}`,
      db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`)!
    );
    db().store.delete(`${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`);
    const token = formatConsentToken(requestId, rawNonce);

    const { res, calls } = fakeResponse();
    await confirmParentalConsent(
      { method: "POST", body: { t: token }, query: {} } as never,
      res as never
    );

    expect(calls.statusCode).toBe(409);
    expect(calls.body).toBe(confirmationFailurePage("missing_age_out_marker"));
    expect(calls.body).not.toMatch(/try again/i);
    expect(calls.body).toContain("delete and reinstall");
    expect(calls.body).toContain("share code");

    // Nothing admitted — the refusal must not have side effects.
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
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

  // Finding 2026-08-28: mail scanners follow GET links (observed live — three
  // valid-link hits in four seconds, no human). The commit therefore lives on POST
  // only; GET serves a form and may touch NOTHING a robot could consume or observe.
  it("the endpoint commits only on POST; GET serves the form; other methods are refused", () => {
    expect(consentEndpointAction("GET")).toBe("serve_form");
    expect(consentEndpointAction("HEAD")).toBe("serve_form"); // scanners often probe HEAD
    expect(consentEndpointAction("get")).toBe("serve_form");
    expect(consentEndpointAction("POST")).toBe("process");
    expect(consentEndpointAction("PUT")).toBe("method_not_allowed");
    expect(consentEndpointAction("DELETE")).toBe("method_not_allowed");
    expect(consentEndpointAction(undefined)).toBe("method_not_allowed");
  });

  it("the interstitial posts the token back and stays generic — no names, no oracle", () => {
    const token = `abc123.${"ab".repeat(16)}`;
    const page = buildConsentInterstitialPage({ token, envLabel: "DEV" });
    expect(page).toContain(`method="post"`);
    expect(page).toContain(`name="t" value="${token}"`);
    expect(page).toContain("I consent");
    // Generic by construction: the builder takes no child or family input, and the
    // page must never embed anything beyond the token the caller already holds.
    expect(page).not.toContain("Speedy");
    expect(page).not.toContain("Hammers");
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
// 3b. Reason-specific parent-facing copy (2026-09-07 audit)
// ---------------------------------------------------------------------------

describe("confirmationFailurePage: truthful copy per commitGuardianConfirmation reason", () => {
  it("missing_age_out_marker tells the parent the truth in plain language — never 'try again'", () => {
    const page = confirmationFailurePage("missing_age_out_marker");
    expect(page).not.toMatch(/try again/i);
    expect(page).toContain("delete and reinstall");
    expect(page).toContain("share code");
    expect(page).toContain("new confirmation email");
    // Plain language: no internal field/flag names or program codenames leak into copy a
    // parent reads.
    expect(page).not.toContain("ageOutYearMonth");
    expect(page).not.toContain("F-14b");
    expect(page).not.toContain("marker");
  });

  it("child_gone, other_family, row_gone, member_gone, and scope_selection_invalid each get distinct, non-generic copy", () => {
    const reasons = [
      "child_gone",
      "other_family",
      "row_gone",
      "member_gone",
      "scope_selection_invalid",
    ] as const;
    const pages = reasons.map((reason) => confirmationFailurePage(reason));

    for (const page of pages) {
      expect(page).not.toContain("Please try the link again in a moment.");
      expect(page).not.toMatch(/try again/i);
    }
    // Textually distinct from each other and from missing_age_out_marker — no accidental
    // aliasing of one reason's copy onto another.
    const allPages = [...pages, confirmationFailurePage("missing_age_out_marker")];
    expect(new Set(allPages).size).toBe(allPages.length);
  });

  it("request_not_pending and an unrecognized reason fall back to the generic copy — deliberately: a retry IS the right move for a same-link confirmation race", () => {
    const generic = confirmationFailurePage(undefined);
    expect(generic).toContain("Please try the link again in a moment.");
    expect(confirmationFailurePage("request_not_pending")).toBe(generic);
    expect(confirmationFailurePage("some_future_reason_nobody_wrote_copy_for_yet")).toBe(
      generic
    );
  });

  it("already_member is intentionally absent from this map — the endpoint special-cases it to the 200 already-confirmed page before any failure copy is chosen", () => {
    expect(confirmationFailurePage("already_member")).toBe(confirmationFailurePage(undefined));
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
// 5b. member_flag lifecycle edges (owner ruling 2026-08-28): expiry removes the
//     member (account survives, sticky protections); the reconcile spares the window.
// ---------------------------------------------------------------------------

describe("member_flag: refusal-by-silence removes the member, never the account", () => {
  function seedFlaggedMember(expiresAtMillis: number): void {
    db().seed("users/flagged", {
      userName: "Flagged",
      isChildAccount: true,
      activeFamilyId: "famM",
      ageOutYearMonth: 203801,
    });
    db().seed("families/famM/members/flagged", {
      role: "scout",
      isChild: true,
      consentPending: true,
    });
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/mf1`, {
      kind: "member_flag",
      familyId: "famM",
      childUserId: "flagged",
      guardianUid: "captain",
      guardianEmail: "captain@example.com",
      childUserName: "Flagged",
      noticeFamilyName: "The Ms",
      expectedAgeOutYearMonth: 203801,
      status: "pending",
      attempts: 0,
      requestedAtMillis: 1_000,
      expiresAtMillis,
      method: "email_plus",
      assuranceLevel: 1,
      nonceHash: hashConsentNonce("cc".repeat(16)),
      ...launchEvidence(),
    });
  }

  it("expiry: member removed, address purged, REVOKED written — the account SURVIVES", async () => {
    seedFlaggedMember(5_000);

    const result = await sweepExpiredConsentRequests(db() as never, 10_000);
    expect(result.expired).toBe(1);

    const request = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/mf1`)!;
    expect(request.status).toBe("expired");
    expect(request.guardianEmail).toBe("__delete__");

    // The membership ends; the person does not.
    expect(db().store.get("families/famM/members/flagged")).toBeUndefined();
    const user = db().store.get("users/flagged")!;
    expect(user.activeFamilyId).toBe("__delete__");
    expect(user.wasEverInFamily).toBe(true);
    expect(user.isChildAccount).toBe(true); // sticky — protections never lift here
    expect(holder.deletedAuthUsers).toEqual([]);

    const revoked = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_REVOKED"
    );
    expect(revoked).toHaveLength(1);
    expect((revoked[0][1].metadata as Record<string, unknown>).reason).toBe(
      "consent_not_obtained"
    );
  });

  it("FR-69(b): expiry also takes the child off any live trip they were sharing", async () => {
    seedFlaggedMember(5_000);
    // Mid-trip when the guardian never answered: the family that made this roster lawful
    // is no longer theirs the moment the membership goes.
    db().seed("trip_sessions/tm", {
      name: "Road trip",
      createdBy: "captain",
      canonicalStatus: "active",
      canonicalParticipants: [
        { userId: "captain", role: "owner", joinedAt: 1, leftAt: null, teamId: null },
        { userId: "flagged", role: "member", joinedAt: 1, leftAt: null, teamId: null },
      ],
    });
    db().seed("trip_sessions/tm/members/captain", { role: "owner", joinedAt: 1 });
    db().seed("trip_sessions/tm/members/flagged", { role: "member", joinedAt: 1 });
    db().seed("trip_sessions/tm/activity_events/join-flagged", {
      sessionId: "tm",
      kind: "participant_joined",
      actorId: "flagged",
      payload: {},
    });

    await sweepExpiredConsentRequests(db() as never, 10_000);

    expect(db().store.get("trip_sessions/tm/members/flagged")).toBeUndefined();
    expect(db().store.get("trip_sessions/tm/members/captain")).toBeTruthy();
    expect(
      db().store.get(
        "trip_sessions/tm/activity_events/coppa-left-family_membership_ended-flagged"
      )
    ).toMatchObject({
      kind: "participant_left",
      payload: { participantId: "flagged", leaveReason: "family_membership_ended" },
    });
  });

  it("the FR-64 reconcile spares the pending window and counts nobody twice", async () => {
    seedFlaggedMember(Date.now() + 60_000); // live request

    const pending = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });
    expect(pending.missingRecord).toEqual([]); // the window is designed, not a defect
    expect(pending.consentedChildren).toBe(0); // excluded, not silently passed

    // Once the request dies without confirmation, the removal (above) clears
    // activeFamilyId, so the child leaves the reconcile's population entirely.
    db().store.set(`${CONSENT_REQUESTS_COLLECTION}/mf1`, {
      ...db().store.get(`${CONSENT_REQUESTS_COLLECTION}/mf1`)!,
      status: "expired",
    });
    db().store.set("users/flagged", {
      ...db().store.get("users/flagged")!,
      activeFamilyId: undefined,
    });
    const after = await reconcileConsentRecords(db() as never, { nowMillis: Date.now() });
    expect(after.missingRecord).toEqual([]);
  });

  it("the consent email speaks the member_flag lifecycle: continue, and removal on silence", () => {
    const content = buildConsentRequestEmailContent({
      familyDisplayName: "The Ms",
      childUserName: "Flagged",
      confirmUrl: "https://example.test/confirm?t=x.y",
      envLabel: "",
      ttlHours: 72,
      kind: "member_flag",
      scopeVector: buildScopeVector(["core"]),
    });
    expect(content.subject).toContain("to continue in");
    expect(content.text).toContain("marked the family member");
    expect(content.text).toContain("removed from the family");
    expect(content.text).not.toContain("pending account information is deleted");
  });

  it("member_gone: the child already left the family before the guardian confirmed — refuses, writes nothing", async () => {
    seedFlaggedMember(Date.now() + 60_000); // live request
    db().store.delete("families/famM/members/flagged");

    const outcome = await confirmGuardianConsent(db(), {
      familyId: "famM",
      childUserId: "flagged",
    });
    expect(outcome).toMatchObject({ committed: false, reason: "member_gone" });
    // Nothing admitted: no guardianship record, no consent audit row.
    expect(db().store.get("users/flagged/private/guardianship")).toBeUndefined();
    const consentRows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    );
    expect(consentRows).toHaveLength(0);
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
      ...launchEvidence(),
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
      scopeVector: buildScopeVector(["core"]),
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

// ---------------------------------------------------------------------------
// 8. F-21 slice 2 — the scope vector and version evidence (FR-65 / FR-103 / FR-64)
// ---------------------------------------------------------------------------

function grantedRows(): Array<Record<string, unknown>> {
  return [...db().store.entries()]
    .filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") && data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    )
    .map(([, data]) => data);
}

function consentRequestDocs(): Array<[string, Record<string, unknown>]> {
  return [...db().store.entries()].filter(([path]) =>
    path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)
  );
}

/** A join child whose row is still `pending` (no approve yet). */
async function childPendingRow(): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const { code } = await run.createShareCode("captain", familyId);
  const { inviteId } = await run.redeemShareCode("kid", code);
  await run.acceptInvite("kid", inviteId);
  const rows = [...db().store.entries()].filter(
    ([path, data]) =>
      path.startsWith(`families/${familyId}/pending/`) && data.status === "pending"
  );
  return { familyId, requestId: rows[0][0].split("/").pop()! };
}

const UPDATE_MESSAGE =
  "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.";

describe("F-21: the join entry point validates the consent text and scopes before any write", () => {
  it.each([
    ["an older consent text version", { consentTextVersion: "1.0.0-2026-08-10" }, "consent_text_outdated"],
    ["a pre-F-21 payload (neither field)", { consentTextVersion: undefined, consentScopes: undefined }, "consent_text_outdated"],
    ["an empty selection", { consentScopes: [] }, "consent_scopes_invalid"],
    ["a frozen scope selected", { consentScopes: ["core", "analytics_internal"] }, "consent_scopes_invalid"],
  ])("%s → failed-precondition with details.reason; row untouched, no request", async (_l, patch, reason) => {
    const { familyId, requestId } = await childPendingRow();

    const error = await run
      .approve("captain", { familyId, requestId, ...CHILD_APPROVAL, ...patch })
      .catch((e) => e);
    expect(error).toMatchObject({
      code: "failed-precondition",
      message: UPDATE_MESSAGE,
      details: { reason },
    });
    expect(db().store.get(`families/${familyId}/pending/${requestId}`)?.status).toBe("pending");
    expect(consentRequestDocs()).toHaveLength(0);
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
  });
});

describe("F-21: consent requests store the evidence at creation, for both kinds", () => {
  it("join_admission: vector, the client's text version, the notice version and policy versions", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    expect(found.data).toMatchObject({ kind: "join_admission", ...launchEvidence() });
    expect(found.data.scopeVector).toEqual({
      core: { state: "granted", practiceVersion: 1 },
      analytics_internal: { state: "unavailable", practiceVersion: 1 },
      ads_child_directed: { state: "unavailable", practiceVersion: 1 },
      location_family_shared: { state: "unavailable", practiceVersion: 1 },
      cross_family_visibility: { state: "unavailable", practiceVersion: 1 },
    });
  });

  it("member_flag: the same evidence", async () => {
    db().seed("families/famM", { name: "The Ms" });
    const { requestId } = await createMemberFlagConsentRequest(db() as never, {
      familyId: "famM",
      childUserId: "flagged",
      guardianUid: "captain",
      guardianRole: "creator",
      guardianEmail: "captain@example.com",
      childUserName: "Flagged",
      expectedAgeOutYearMonth: 203801,
      scopeVector: buildScopeVector(["core"]),
      consentTextVersion: CONSENT_TEXT_VERSION,
    });
    expect(db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${requestId}`)).toMatchObject({
      kind: "member_flag",
      ...launchEvidence(),
    });
  });
});

describe("F-21: a live request is reused only for identical evidence", () => {
  function seedLive(id: string, extra: Record<string, unknown>): void {
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/${id}`, {
      kind: "join_admission",
      familyId: "famR",
      childUserId: "kid",
      guardianUid: "captain",
      guardianEmail: "captain@example.com",
      status: "pending",
      expiresAtMillis: Date.now() + 60_000,
      ...extra,
    });
  }
  const create = () =>
    createConsentRequestForApproval(db() as never, {
      familyId: "famR",
      childUserId: "kid",
      joinRequestId: "row1",
      guardianUid: "captain",
      guardianRole: "creator",
      guardianEmail: "captain@example.com",
      newRole: "scout",
      childUserName: "Speedy",
      scopeVector: buildScopeVector(["core"]),
      consentTextVersion: CONSENT_TEXT_VERSION,
    });

  it("an identical live request is reused — no new request, no new email", async () => {
    seedLive("same", launchEvidence());
    await expect(create()).resolves.toEqual({ requestId: "same", reusedExisting: true });
    expect(consentRequestDocs()).toHaveLength(1);
  });

  it.each([
    ["no vector (a pre-F-21 request)", { ...launchEvidence(), scopeVector: undefined }],
    [
      "a different vector",
      {
        ...launchEvidence(),
        scopeVector: {
          ...buildScopeVector(["core"]),
          core: { state: "granted", practiceVersion: 2 },
        },
      },
    ],
    ["a different consent text version", { ...launchEvidence(), consentTextVersion: "2026-01-01.old" }],
    ["a different notice text version", { ...launchEvidence(), noticeTextVersion: "2026-01-01.notice" }],
    [
      "different policy versions",
      { ...launchEvidence(), policyVersions: { ...CONSENT_POLICY_VERSIONS, privacyPolicy: "old" } },
    ],
  ])("%s is superseded (address and link nonce purged) and a fresh request is made", async (_l, evidence) => {
    // Still queued: superseded before its email trigger ran, so no claim strips the nonce.
    seedLive("old", { ...(evidence as Record<string, unknown>), pendingLinkNonce: "ab".repeat(16) });
    const result = await create();
    expect(result.reusedExisting).toBe(false);
    expect(result.requestId).not.toBe("old");
    const old = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/old`)!;
    expect(old.status).toBe("superseded");
    expect(old.guardianEmail).toBe("__delete__");
    expect(old.pendingLinkNonce).toBe("__delete__");
    expect(db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${result.requestId}`)).toMatchObject({
      status: "pending",
      ...launchEvidence(),
    });
  });

  it("the predicate ignores key order (Firestore maps are unordered)", () => {
    const reordered = {
      ...launchEvidence(),
      policyVersions: {
        privacyPolicy: CONSENT_POLICY_VERSIONS.privacyPolicy,
        termsOfService: CONSENT_POLICY_VERSIONS.termsOfService,
      },
    };
    expect(
      consentRequestEvidenceMatches(reordered, {
        scopeVector: buildScopeVector(["core"]),
        consentTextVersion: CONSENT_TEXT_VERSION,
        noticeTextVersion: CONSENT_NOTICE_TEXT_VERSION,
        policyVersions: CONSENT_POLICY_VERSIONS,
      })
    ).toBe(true);
  });
});

describe("F-21: the email trigger claims only a pending request with a valid vector", () => {
  function seedQueued(id: string, extra: Record<string, unknown>): void {
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/${id}`, {
      status: "pending",
      emailDelivery: { state: "queued" },
      pendingLinkNonce: "ab".repeat(16),
      ...launchEvidence(),
      ...extra,
    });
  }
  const claim = (id: string) =>
    claimConsentRequestEmail(
      db() as never,
      db().collection(CONSENT_REQUESTS_COLLECTION).doc(id) as never
    );

  it("claims a pending request with a valid vector and strips the raw nonce", async () => {
    seedQueued("ok", {});
    // The claim hands the trigger the vector it validated; the email restates exactly that.
    await expect(claim("ok")).resolves.toEqual({
      kind: "send",
      nonce: "ab".repeat(16),
      scopeVector: buildScopeVector(["core"]),
    });
    const doc = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/ok`)!;
    expect(doc.emailDelivery).toEqual({ state: "sending" });
    expect(doc.pendingLinkNonce).toBe("__delete__");
  });

  it("skips a request superseded before the trigger ran, and leaves it alone", async () => {
    seedQueued("gone", { status: "superseded" });
    await expect(claim("gone")).resolves.toEqual({ kind: "skipped" });
    expect(db().store.get(`${CONSENT_REQUESTS_COLLECTION}/gone`)!.emailDelivery).toEqual({
      state: "queued",
    });
  });

  it("refuses a request with no vector: delivery failed, nonce dropped, nothing to send", async () => {
    seedQueued("novector", { scopeVector: undefined });
    await expect(claim("novector")).resolves.toEqual({ kind: "refused" });
    const doc = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/novector`)!;
    expect((doc.emailDelivery as Record<string, unknown>).state).toBe("failed");
    expect(typeof (doc.emailDelivery as Record<string, unknown>).failedAtMillis).toBe("number");
    expect(doc.pendingLinkNonce).toBe("__delete__");
  });

  it("a second claim of the same request is skipped (trigger retries never double-send)", async () => {
    seedQueued("twice", {});
    await claim("twice");
    db().store.set(`${CONSENT_REQUESTS_COLLECTION}/twice`, {
      ...db().store.get(`${CONSENT_REQUESTS_COLLECTION}/twice`)!,
      pendingLinkNonce: undefined,
    });
    await expect(claim("twice")).resolves.toEqual({ kind: "skipped" });
  });
});

describe("F-21: both FR-64 commits record the evidence from the transaction's fresh read", () => {
  // A valid but non-current policy map, written onto the stored request AFTER creation:
  // if the commit recorded current constants (or anything but the fresh read), it would
  // not carry this value.
  const STORED_POLICY = { termsOfService: "tos-at-request", privacyPolicy: "pp-at-request" };

  function setStoredPolicy(requestId: string): void {
    const path = `${CONSENT_REQUESTS_COLLECTION}/${requestId}`;
    db().store.set(path, { ...db().store.get(path)!, policyVersions: STORED_POLICY });
  }

  function expectedEvidence(requestId: string): Record<string, unknown> {
    return {
      consentScopes: buildScopeVector(["core"]),
      consentTextVersion: CONSENT_TEXT_VERSION,
      noticeTextVersion: CONSENT_NOTICE_TEXT_VERSION,
      policyVersions: STORED_POLICY,
      consentRequestId: requestId,
    };
  }

  function seedMemberFlag(): void {
    db().seed("families/famM", { name: "The Ms", creatorId: "captain", status: "active" });
    db().seed("families/famM/members/captain", { role: "creator" });
    db().seed("users/flagged", {
      userName: "Flagged",
      isChildAccount: true,
      activeFamilyId: "famM",
    });
    db().seed("families/famM/members/flagged", {
      role: "scout",
      isChild: true,
      consentPending: true,
    });
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/mf2`, {
      kind: "member_flag",
      familyId: "famM",
      childUserId: "flagged",
      guardianUid: "captain",
      guardianRole: "creator",
      guardianEmail: "captain@example.com",
      expectedAgeOutYearMonth: 203801,
      status: "pending",
      expiresAtMillis: Date.now() + 60_000,
      method: "email_plus",
      assuranceLevel: 1,
      ...launchEvidence(),
    });
  }

  it("join and member_flag write identical evidence into the GRANTED row and guardianship", async () => {
    const { familyId } = await childAwaiting();
    const joinRequestId = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!.requestId;
    setStoredPolicy(joinRequestId);
    expect((await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed).toBe(
      true
    );

    seedMemberFlag();
    setStoredPolicy("mf2");
    expect(
      (await confirmGuardianConsent(db(), { familyId: "famM", childUserId: "flagged" })).committed
    ).toBe(true);

    const rows = grantedRows();
    expect(rows).toHaveLength(2);
    const joinRow = rows.find((row) => row.subjectId === "kid")!;
    const flagRow = rows.find((row) => row.subjectId === "flagged")!;
    expect(joinRow.metadata).toMatchObject(expectedEvidence(joinRequestId));
    expect(flagRow.metadata).toMatchObject(expectedEvidence("mf2"));
    for (const row of [joinRow, flagRow]) {
      expect(row.metadata).not.toHaveProperty("consentScope");
    }

    for (const [child, requestId] of [
      ["kid", joinRequestId],
      ["flagged", "mf2"],
    ] as const) {
      const guardianship = db().store.get(`users/${child}/private/guardianship`)!;
      expect(guardianship).toMatchObject(expectedEvidence(requestId));
      expect(guardianship.consentScopesUpdatedAtMillis).toBe(guardianship.grantedAtMillis);
      expect((guardianship.consentScopes as Record<string, any>).core.state).toBe("granted");
    }
  });

  type Mutation = (vector: Record<string, any>) => void;
  const tamper: Array<[string, Mutation]> = [
    ["a frozen scope granted", (v) => (v.analytics_internal.state = "granted")],
    ["core missing", (v) => delete v.core],
    ["a practice-version drift", (v) => (v.cross_family_visibility.practiceVersion = 2)],
  ];

  it.each(tamper)(
    "join: a stored vector with %s refuses with scope_selection_invalid and writes nothing",
    async (_l, mutate) => {
      const { familyId, requestId: rowId } = await childAwaiting();
      const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
      const path = `${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`;
      const vector = JSON.parse(JSON.stringify(found.data.scopeVector));
      mutate(vector);
      db().store.set(path, { ...db().store.get(path)!, scopeVector: vector });
      const before = new Map(db().store);

      const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
      expect(outcome).toEqual({ committed: false, reason: "scope_selection_invalid" });
      expect(db().store).toEqual(before);
      expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
      expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
      expect(db().store.get("users/kid/private/guardianship")).toBeUndefined();
      expect(db().store.get(`families/${familyId}/pending/${rowId}`)?.status).toBe(
        JOIN_REQUEST_AWAITING_GUARDIAN_STATUS
      );
      expect(db().store.get(path)?.status).toBe("pending");
      expect(grantedRows()).toHaveLength(0);
    }
  );

  it.each(tamper)(
    "member_flag: a stored vector with %s refuses with scope_selection_invalid and writes nothing",
    async (_l, mutate) => {
      seedMemberFlag();
      const path = `${CONSENT_REQUESTS_COLLECTION}/mf2`;
      const vector = JSON.parse(JSON.stringify(db().store.get(path)!.scopeVector));
      mutate(vector);
      db().store.set(path, { ...db().store.get(path)!, scopeVector: vector });
      const before = new Map(db().store);

      const outcome = await confirmGuardianConsent(db(), {
        familyId: "famM",
        childUserId: "flagged",
      });
      expect(outcome).toEqual({ committed: false, reason: "scope_selection_invalid" });
      expect(db().store).toEqual(before);
      expect(db().store.get("families/famM/members/flagged")?.consentPending).toBe(true);
      expect(db().store.get("users/flagged/private/guardianship")).toBeUndefined();
      expect(grantedRows()).toHaveLength(0);
    }
  );

  it("a request with no vector at all (pre-F-21) refuses the same way", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    const path = `${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`;
    db().store.set(path, { ...db().store.get(path)!, scopeVector: undefined });
    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toEqual({ committed: false, reason: "scope_selection_invalid" });
    expect(grantedRows()).toHaveLength(0);
  });

  it("an injected failure inside the transaction leaves member, activeFamilyId, audit row and guardianship ALL absent", async () => {
    const { familyId } = await childAwaiting();
    const { FakeTransaction } = await import("./testSupport/fakeFirestore");
    const originalSet = FakeTransaction.prototype.set;
    // Throw on the LAST write the join commit queues (the audit row), after the member
    // doc, the user update, the row, the request and guardianship are already queued.
    const spy = vi
      .spyOn(FakeTransaction.prototype, "set")
      .mockImplementation(function (this: unknown, ref: any, data: any, options?: any) {
        if (String(ref.path).startsWith("audit_logs/")) {
          throw new Error("injected commit failure");
        }
        return originalSet.call(this as never, ref, data, options);
      });
    try {
      await expect(
        confirmGuardianConsent(db(), { familyId, childUserId: "kid" })
      ).rejects.toThrow("injected commit failure");
    } finally {
      spy.mockRestore();
    }
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
    expect(db().store.get("users/kid/private/guardianship")).toBeUndefined();
    expect(grantedRows()).toHaveLength(0);
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// F-21 slice 3: the endpoint, the trigger and the restatements they serve
// ---------------------------------------------------------------------------

describe("F-21 slice 3: the notices restate the selection on every surface", () => {
  function fakeResponse() {
    const calls: { statusCode?: number; body?: string } = {};
    const res = {
      set: () => res,
      status(code: number) {
        calls.statusCode = code;
        return res;
      },
      send(body: string) {
        calls.body = body;
        return res;
      },
    };
    return { res, calls };
  }

  /** Moves a request to a shape-valid id (fake auto-ids carry an underscore) and returns its token. */
  function cleanToken(fromId: string, toId: string, nonce: string): string {
    const from = `${CONSENT_REQUESTS_COLLECTION}/${fromId}`;
    db().store.set(`${CONSENT_REQUESTS_COLLECTION}/${toId}`, db().store.get(from)!);
    db().store.delete(from);
    return formatConsentToken(toId, nonce);
  }

  async function post(token: string) {
    const { res, calls } = fakeResponse();
    await confirmParentalConsent({ method: "POST", body: { t: token }, query: {} } as never, res as never);
    return calls;
  }

  it("GET serves the restatement before the button and performs NO Firestore read or write", async () => {
    const { FakeDocumentRef, FakeTransaction, FakeQuery, FakeCollectionRef } = await import(
      "./testSupport/fakeFirestore"
    );
    const spies = [
      vi.spyOn(db(), "collection"),
      vi.spyOn(db(), "collectionGroup"),
      vi.spyOn(db(), "runTransaction"),
      vi.spyOn(db(), "batch"),
      vi.spyOn(FakeDocumentRef.prototype, "get"),
      vi.spyOn(FakeTransaction.prototype, "get"),
      vi.spyOn(FakeQuery.prototype, "get"),
      vi.spyOn(FakeCollectionRef.prototype, "get"),
    ];
    const before = new Map(db().store);
    try {
      const { res, calls } = fakeResponse();
      await confirmParentalConsent(
        { method: "GET", query: { t: `abc123.${"ab".repeat(16)}` } } as never,
        res as never
      );
      expect(calls.statusCode).toBe(200);
      for (const key of [
        "notice.interstitial.scopes_heading",
        "notice.interstitial.scope_core",
        "notice.scopes_unavailable",
      ] as const) {
        expect(calls.body).toContain(NOTICE_DECK[key].replace(/'/g, "&#39;"));
      }
      for (const spy of spies) expect(spy).not.toHaveBeenCalled();
      expect(db().store).toEqual(before);
    } finally {
      for (const spy of spies) spy.mockRestore();
    }
  });

  it("POST success (join) restates the agreement with the join body", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    const token = cleanToken(found.requestId, "reqjoin", found.data.pendingLinkNonce as string);

    const calls = await post(token);

    expect(calls.statusCode).toBe(200);
    expect(calls.body).toBe(consentConfirmedPage("join_admission"));
    expect(calls.body).toContain(escapeHtml(NOTICE_DECK["notice.confirmed.title"]));
    expect(calls.body).toContain(escapeHtml(NOTICE_DECK["notice.confirmed.body.join"]));
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(familyId);
  });

  it("POST success (member_flag) restates the agreement with the stays-active body", async () => {
    db().seed("families/famM", { name: "The Ms", creatorId: "captain", status: "active" });
    db().seed("families/famM/members/captain", { role: "creator" });
    db().seed("users/flagged", {
      userName: "Flagged",
      isChildAccount: true,
      activeFamilyId: "famM",
      ageOutYearMonth: 203801,
    });
    db().seed("families/famM/members/flagged", { role: "scout", isChild: true, consentPending: true });
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/reqflag`, {
      kind: "member_flag",
      familyId: "famM",
      childUserId: "flagged",
      guardianUid: "captain",
      guardianRole: "creator",
      guardianEmail: "captain@example.com",
      expectedAgeOutYearMonth: 203801,
      status: "pending",
      attempts: 0,
      expiresAtMillis: Date.now() + 60_000,
      method: "email_plus",
      assuranceLevel: 1,
      nonceHash: hashConsentNonce("cc".repeat(16)),
      ...launchEvidence(),
    });

    const calls = await post(formatConsentToken("reqflag", "cc".repeat(16)));

    expect(calls.statusCode).toBe(200);
    expect(calls.body).toBe(consentConfirmedPage("member_flag"));
    expect(calls.body).toContain(escapeHtml(NOTICE_DECK["notice.confirmed.body.member_flag"]));
    expect(calls.body).not.toContain(escapeHtml(NOTICE_DECK["notice.confirmed.body.join"]));
  });

  it("POST: a stored vector that fails the re-check gets the scope_selection_invalid page (409), not the generic retry copy", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    const path = `${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`;
    const vector = JSON.parse(JSON.stringify(found.data.scopeVector));
    vector.analytics_internal.state = "granted";
    db().store.set(path, { ...db().store.get(path)!, scopeVector: vector });
    const token = cleanToken(found.requestId, "reqbad", found.data.pendingLinkNonce as string);

    const calls = await post(token);

    expect(calls.statusCode).toBe(409);
    expect(calls.body).toBe(confirmationFailurePage("scope_selection_invalid"));
    expect(calls.body).toContain(escapeHtml(NOTICE_DECK["notice.failure.scope_selection_invalid.title"]));
    expect(calls.body).toContain(escapeHtml(NOTICE_DECK["notice.failure.scope_selection_invalid.body"]));
    expect(calls.body).not.toContain("Please try the link again in a moment.");
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
  });

  describe("the onCreate trigger emails the restatement of the request's own vector", () => {
    const savedEnv = { ...process.env };
    beforeEach(() => {
      process.env.GCLOUD_PROJECT = "demo-test";
      process.env.RESEND_API_KEY = "test-key";
      process.env.WELCOME_EMAIL_FROM = "noreply@example.test";
    });

    async function runTrigger(id: string): Promise<void> {
      const ref = db().collection(CONSENT_REQUESTS_COLLECTION).doc(id);
      const snapshot = { id, ref, data: () => db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${id}`) };
      try {
        await (onConsentRequestCreatedSendEmail as unknown as {
          run: (snap: unknown, ctx: unknown) => Promise<void>;
        }).run(snapshot, { params: { requestId: id } });
      } finally {
        process.env = { ...savedEnv };
      }
    }

    it.each([
      ["join_admission", "notice.request.scope_core.join"],
      ["member_flag", "notice.request.scope_core.member_flag"],
    ] as const)("%s: the sent email restates core and the four unavailable scopes", async (kind, coreKey) => {
      db().seed(`${CONSENT_REQUESTS_COLLECTION}/req1`, {
        kind,
        status: "pending",
        guardianEmail: "captain@example.com",
        childUserName: "Speedy",
        noticeFamilyName: "Hammers",
        emailDelivery: { state: "queued" },
        pendingLinkNonce: "ab".repeat(16),
        ...launchEvidence(),
      });

      await runTrigger("req1");

      expect(holder.sentEmails).toHaveLength(1);
      const email = holder.sentEmails[0];
      for (const key of ["notice.request.scopes_heading", coreKey, "notice.scopes_unavailable"] as const) {
        expect(email.text).toContain(NOTICE_DECK[key]);
      }
      // The fake stores a dotted update path as a literal key (real Firestore nests it).
      expect(db().store.get(`${CONSENT_REQUESTS_COLLECTION}/req1`)!["emailDelivery.state"]).toBe(
        "sent"
      );
    });

    it("a request whose stored vector fails validation sends nothing", async () => {
      const vector = buildScopeVector(["core"]) as Record<string, any>;
      vector.ads_child_directed.state = "granted";
      db().seed(`${CONSENT_REQUESTS_COLLECTION}/req2`, {
        status: "pending",
        guardianEmail: "captain@example.com",
        emailDelivery: { state: "queued" },
        pendingLinkNonce: "ab".repeat(16),
        ...launchEvidence(),
        scopeVector: vector,
      });

      await runTrigger("req2");

      expect(holder.sentEmails).toHaveLength(0);
      expect(
        (db().store.get(`${CONSENT_REQUESTS_COLLECTION}/req2`)!.emailDelivery as Record<string, unknown>).state
      ).toBe("failed");
    });
  });

  it("the plus notice restates the retained vector per kind, and a confirmed request without one is retried, never sent", async () => {
    const base = {
      familyId: "famX",
      childUserId: "kid",
      guardianUid: "captain",
      guardianEmail: "captain@example.com",
      status: "confirmed",
      confirmedAtMillis: 1_000,
      childUserName: "Speedy",
      noticeFamilyName: "Hammers",
    };
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/pj`, { ...base, ...launchEvidence() });
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/pm`, { ...base, kind: "member_flag", ...launchEvidence() });
    db().seed(`${CONSENT_REQUESTS_COLLECTION}/pnone`, { ...base });
    const sendEmail = vi.fn(async (_params: Record<string, string>) => ({ providerMessageId: "msg" }));

    const result = await sendDueConsentPlusNotices(db() as never, {
      nowMillis: 1_000 + CONSENT_PLUS_NOTICE_DELAY_MS,
      delayMillis: CONSENT_PLUS_NOTICE_DELAY_MS,
      envLabel: "",
      sendEmail: sendEmail as never,
    });

    expect(result).toEqual({ sent: 2, failed: 1, abandoned: 0 });
    const texts = sendEmail.mock.calls.map((call) => call[0].text);
    expect(texts.some((t) => t.includes(NOTICE_DECK["notice.plus.scope_core.join"]))).toBe(true);
    expect(texts.some((t) => t.includes(NOTICE_DECK["notice.plus.scope_core.member_flag"]))).toBe(true);
    for (const text of texts) {
      expect(text).toContain(NOTICE_DECK["notice.plus.scopes_heading"]);
      expect(text).toContain(NOTICE_DECK["notice.plus.scopes_unavailable"]);
    }
    const none = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/pnone`)!;
    expect(none.plusNoticeAttempts).toBe(1);
    expect(none.plusNoticeSentAtMillis).toBeUndefined();
    expect(none.guardianEmail).toBe("captain@example.com"); // kept for the retry path
  });
});
