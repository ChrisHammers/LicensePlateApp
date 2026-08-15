import { describe, it, expect, vi } from "vitest";
import { deleteRevenueCatCustomer } from "./revenueCat";

function fakeFetch(status: number, body = ""): typeof fetch {
  return vi.fn(async () => {
    return {
      status,
      ok: status >= 200 && status < 300,
      text: async () => body,
    } as unknown as Response;
  }) as unknown as typeof fetch;
}

describe("deleteRevenueCatCustomer", () => {
  it("calls DELETE /v1/subscribers/{app_user_id} with a bearer secret key", async () => {
    const fetchImpl = fakeFetch(200);

    await deleteRevenueCatCustomer({
      apiKey: "sk_test_123",
      appUserId: "uid_abc",
      fetchImpl,
    });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, options] = (fetchImpl as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toBe("https://api.revenuecat.com/v1/subscribers/uid_abc");
    expect(options).toMatchObject({
      method: "DELETE",
      headers: { Authorization: "Bearer sk_test_123" },
    });
  });

  it("URL-encodes the app_user_id", async () => {
    const fetchImpl = fakeFetch(200);

    await deleteRevenueCatCustomer({
      apiKey: "sk_test_123",
      appUserId: "uid/with space",
      fetchImpl,
    });

    const [url] = (fetchImpl as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toBe(
      "https://api.revenuecat.com/v1/subscribers/uid%2Fwith%20space"
    );
  });

  it("treats 200 as deleted", async () => {
    const result = await deleteRevenueCatCustomer({
      apiKey: "sk_test_123",
      appUserId: "uid_abc",
      fetchImpl: fakeFetch(200),
    });
    expect(result).toEqual({ outcome: "deleted" });
  });

  it("treats 404 (never identified to RevenueCat) as not_found, not an error", async () => {
    const result = await deleteRevenueCatCustomer({
      apiKey: "sk_test_123",
      appUserId: "uid_never_purchased",
      fetchImpl: fakeFetch(404),
    });
    expect(result).toEqual({ outcome: "not_found" });
  });

  it("throws on a vendor error so the caller can treat it as retryable", async () => {
    await expect(
      deleteRevenueCatCustomer({
        apiKey: "sk_test_123",
        appUserId: "uid_abc",
        fetchImpl: fakeFetch(500, "internal error"),
      })
    ).rejects.toThrow(/500/);
  });

  it("throws on an auth error (bad/rotated key)", async () => {
    await expect(
      deleteRevenueCatCustomer({
        apiKey: "sk_bad",
        appUserId: "uid_abc",
        fetchImpl: fakeFetch(401, "invalid api key"),
      })
    ).rejects.toThrow(/401/);
  });
});
