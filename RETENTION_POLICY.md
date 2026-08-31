# RoadTrip Royale — Data Retention Policy (NP-3)

**Status: OWNER-APPROVED 2026-08-30 — not yet published** (publication rides NP-2; counsel review rides the standing launch caveat). Drafted 2026-08-30 from
`COPPA_SRS_v3.md` FR-77/FR-78/OD-3 and the shipped retention code. This document is the
§312.10 *written data retention policy* the amended COPPA Rule requires; the
public-facing rendering ships with NP-2's notice-text work and must match this
document — published BOTH on the website's privacy-policy page and in the in-app
policy views (localized ×3); §312.10 requires the retention practices be stated in
the public online notice, not only held internally. Counsel review rides the standing
launch caveat in `COPPA_COUNSEL_MEMO.md`.

**Machine-checked:** the retention windows in the table below are pinned against the
constants in `functions/src` by `retentionPolicyParity.test.ts` — if code and policy
drift, the functions suite fails.

---

## 1. Principles

1. **No indefinite retention.** Personal information collected from children is
   retained only as long as reasonably necessary for the specific, disclosed purpose
   it was collected for, and is then deleted by scheduled, automated jobs — not by
   manual process.
2. **Deletion on direction, ahead of any schedule.** A parent may direct deletion of
   their child's information at any time (in-app: the removal choice, the child
   privacy screen, and the "children you've consented for" list), and any user may
   delete their own account. Directed deletion runs immediately and is not subject to
   the windows below.
3. **Fail toward retention only while a decision is live.** Automated deletion is
   vetoed while a consent decision is actually in flight (a pending or
   awaiting-guardian request), so a family mid-process is never deleted out from
   under its own consent flow. Every other ambiguity resolves toward deletion at the
   window.
4. **Windows are enforced in code.** Each retention class below names the purpose for
   collection, the business need for retention, and the deletion timeframe — the
   three elements §312.10 requires — and each enforced class maps to a named
   scheduled job.

## 2. Retention schedule

| # | Data class | Purpose of collection | Business need for retention | Deletion timeframe | Enforcement |
|---|---|---|---|---|---|
| 1 | **Redemption-window child accounts** (account provisioned when a child enters a family share code, before parental consent) | Obtaining verifiable parental consent (§312.5(c)(1)) | Exists only while consent is being sought | Deleted **immediately** on decline or request expiry; **7-day** scheduled backstop for anything the inline path missed | `purgeExpiredProvisionalChildAccounts` (nightly) — ENFORCED |
| 2 | **Consent requests** (guardian email, hashed confirmation nonce) | Delivering the direct notice and capturing the guardian's confirmation | Only while the confirmation link is valid | Request expires after **72 hours**; expiry purges the guardian email and deletes the never-consented child inline | Confirmation endpoint (real-time) + `expireLapsedConsentRequests` (nightly) — ENFORCED |
| 3 | **Revoked-but-retained child accounts** (parent chose "remove, keep their data") | Preserving the child's account and gameplay at the parent's §312.6(a)(2) direction, with review/deletion rights intact | The parent's stated choice; supports re-admission and later review | **12 months** after revocation (owner-decided 2026-08-30), then full deletion by the abandonment backstop; the parent's own delete remains the primary path | `purgeAbandonedRevokedChildAccounts` (nightly) — ENFORCED |
| 4 | **Invites and share codes** | Family/trip joining flows | Only until acted on or expired; kept briefly post-expiry so the UI can show the outcome | Status-flipped at expiry; hard-deleted **30 days** after expiry | `purgeExpiredInvitesAndCodes` (nightly) — ENFORCED |
| 5 | **Audit logs (general)** | Operations, abuse investigation, support | Recency-bounded diagnostic value | **12 months** | `purgeExpiredAuditLogs` (nightly) — ENFORCED |
| 6 | **Consent and lifecycle audit records** (declarations, grants, corrections, revocations, deletions; uid-only, no personal details) | Legal evidence that consent was sought, obtained, corrected, or revoked (§312.5) | **Exempt from purging — retained for the life of the service.** Rationale: these rows are the operator's proof of compliance; deleting them would destroy the evidence the Rule's consent framework depends on. They carry identifiers only (no names, no contact information), and account deletion removes the personal information they refer to. | Not time-purged | Exemption list in `retentionCore.ts` — ENFORCED |
| 7 | **Account data on deletion request** (profile, private subcollection, progression, achievements, public stats, search rows, rate-limit counters) | Providing the service | None once deletion is directed | **Immediate** on parent-directed or self-directed deletion | `executeAccountDeletionForUser` — ENFORCED |
| 8 | **Shared gameplay records** (trips, discoveries, scores involving other players) | The shared trip history belongs to every participant | Other participants' legitimate access to their own trip history | On account deletion, the departing player's identifying references are **de-identified in place** (tombstoned), never left keyed to the deleted account; the trip survives for the remaining participants | `deidentifyUserResidue` inside every deletion — ENFORCED |
| 9 | **Third-party data (RevenueCat purchases)** | Subscription entitlement | None once the account is deleted | Vendor customer record deleted **in the same cascade** as account deletion | `executeAccountDeletionForUser` FR-78(a) phase — ENFORCED (inert until the production API key is provisioned; recorded no-op meanwhile) |
| 10 | **Third-party data (Google Analytics)** | Aggregate product analytics | None per-user; no account identifier is ever sent (child sessions send nothing pre-consent) | Device-side analytics data **reset at account deletion**; server-side data ages out under Google's configured GA4 retention window | Client `resetAnalyticsData()` at deletion + GA4 retention setting — documented mechanism (FR-78(b) decision) |
| 11 | **Inactive accounts** | Providing the service | Road-trip play is episodic by nature — a year between family trips is normal use, not abandonment — and a child's account holds their side of the family's shared trip history, with the parent's review and deletion rights live the entire time | **36 months** without authenticated activity, all ages (owner-decided 2026-08-30; a bounded window with a parent in control throughout is not indefinite retention) | ADOPTED — automated job ships with the remaining FR-77 work before launch |
| 12 | **Location payloads on ended-trip events** (coarse find locations; adult accounts only — child events never carry location) | Showing where a discovery happened during the trip's life | The place-trail's value decays; the trip history itself (names, discoveries, scores) is the product's purpose and is retained with the account | Location keys stripped from events older than **36 months** (owner-decided 2026-08-30); gameplay bookkeeping untouched | ADOPTED — automated job ships with the remaining FR-77 work before launch |

Never-consented children who never enter a share code have **no server-side data at
all** under the local-first model — there is nothing to schedule.

## 3. Review

This policy is reviewed with the written information-security program
(`SECURITY_PROGRAM.md`, §312.8(b) — FR-82, pending) on that program's annual cadence,
and whenever a retention class is added or a window changes. Changes to windows are
owner decisions recorded in `COPPA_SRS_v3.md` (OD-3 lineage) before the constants
change.

---

*Draft notes (strip before publication): row 12's window is owner-decided (36
months, 2026-08-30 — deliberately long so it can be shortened later if it matters);
row 11 is owner-decided too (36 months all ages, 2026-08-30, with the episodic-use rationale stated in the row). Both are adopted here as policy but
not yet automated — their jobs are the remaining FR-77
build items and must land before launch or these rows must be removed from the
published text. Row 9's vendor deletion is live code behind an unprovisioned
production API key (see `currentRevenueCatApiKey`). The parity test pins rows 1–5's
numbers to the shipped constants; rows 11–12 join it when their constants exist.*
