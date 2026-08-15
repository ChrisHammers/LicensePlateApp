/**
 * RevenueCat REST API v1 customer deletion (COPPA FR-78(a) — §312.6 vendor deletion).
 *
 * `DELETE /v1/subscribers/{app_user_id}` erases the customer from RevenueCat entirely. This
 * is distinct from the client's `Purchases.logOut()`, which only clears the local SDK's
 * cached identity and leaves the vendor's copy of the record untouched.
 *
 * Requires a project *secret* API key (RevenueCat dashboard -> API keys -> "Secret" key,
 * distinct from the public SDK key already embedded in the client). `app_user_id` is the
 * Firebase uid: that is what `RevenueCatEntitlementBridge.identify(userId:)` passes to
 * `Purchases.shared.logIn(uid)` (`DeferredSDKStartupService.swift` feeds it
 * `Auth.auth().currentUser?.uid`).
 *
 * A 404 means RevenueCat has never heard of this uid (account never opened the paywall) —
 * that is success, not failure, so deleting a never-purchasing account is a clean no-op.
 */

export type FetchLike = typeof fetch;

export interface DeleteRevenueCatCustomerParams {
  apiKey: string;
  appUserId: string;
  /** Injected for tests; defaults to the global `fetch`. */
  fetchImpl?: FetchLike;
}

/** "not_found" covers both a never-purchasing account and a re-run after a prior success. */
export type RevenueCatDeletionOutcome = "deleted" | "not_found";

export interface DeleteRevenueCatCustomerResult {
  outcome: RevenueCatDeletionOutcome;
}

export async function deleteRevenueCatCustomer(
  params: DeleteRevenueCatCustomerParams
): Promise<DeleteRevenueCatCustomerResult> {
  const doFetch = params.fetchImpl ?? fetch;

  const response = await doFetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(params.appUserId)}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${params.apiKey}`,
      },
    }
  );

  if (response.status === 404) {
    return { outcome: "not_found" };
  }
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`RevenueCat customer deletion failed (${response.status}): ${body}`);
  }
  return { outcome: "deleted" };
}
