//
//  ChildPremiumInfoView.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-34-amended / owner decision D-14): premium surfaces stay VISIBLE
//  for child sessions and render this informational content in the same slot the
//  adult paywall uses — same visual chrome family, but NO pricing, NO
//  purchase/restore, NO upgrade CTA. Copy is informational and parent-directed,
//  never urgent or nagging. The purchase flow itself stays blocked for children
//  (`PaywallViewModel.purchase()` guard).
//
//  Family elevation is mentioned only where mechanically true — all three sheet
//  contexts qualify: trip limits and saved-trip caps key off
//  `EntitlementState.effectiveTier` (max of own and family-creator tier), and
//  gold/royale avatar unlocks do too (`EntitlementService.isUnlocked`).
//
//  No analytics fire from these surfaces: an event that exists only for child
//  sessions on the child's own instance is forbidden (SRS §12 / FR-21).
//

import SwiftUI

/// Which content a premium sheet slot renders (FR-34-amended: a child never sees
/// purchase UI; the slot itself still presents so the situation is explained).
enum ChildPremiumSheetVariant: Equatable {
    case paywall
    case childInfo

    static func variant(purchasesSuppressed: Bool) -> ChildPremiumSheetVariant {
        purchasesSuppressed ? .childInfo : .paywall
    }
}

/// The premium surface being explained. Drives title/body and the info rows.
enum ChildPremiumInfoContext: Equatable {
    case tripLimit
    case savedTrips
    case premiumIntro

    var titleKey: String {
        switch self {
        case .tripLimit: return "child_gate.trip_limit.title"
        case .savedTrips: return "Older saved trips are locked"
        case .premiumIntro: return "child_gate.premium.intro_title"
        }
    }

    var bodyKey: String {
        switch self {
        case .tripLimit: return "child_gate.trip_limit.body"
        case .savedTrips: return "child_gate.saved_trips.body"
        case .premiumIntro: return "child_gate.premium.intro_body"
        }
    }

    /// Parent-directed info rows. The first is always the upgrades-are-handled-by-
    /// your-parent line; the second is the family-elevation line, phrased per
    /// context and included only because it is mechanically true for all three.
    var infoRowKeys: [String] {
        switch self {
        case .tripLimit:
            return ["child_gate.premium.upgrades", "child_gate.trip_limit.family"]
        case .savedTrips, .premiumIntro:
            return ["child_gate.premium.upgrades", "child_gate.premium.family_tier"]
        }
    }
}

struct ChildPremiumInfoView: View {
    let context: ChildPremiumInfoContext
    /// Bottom button title; defaults to "Done" (onboarding passes "Continue").
    var primaryActionTitle: String? = nil
    let onDismiss: () -> Void

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Text(context.titleKey.localized)
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .accessibleHeader(context.titleKey.localized)
                            .multilineTextAlignment(.center)

                        Text(context.bodyKey.localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(context.infoRowKeys.enumerated()), id: \.offset) { index, key in
                                infoRow(
                                    icon: index == 0 ? "figure.and.child.holdinghands" : "star.circle.fill",
                                    text: key.localized
                                )
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 32)
                    .padding(.bottom, 24)
                }

                Button {
                    onDismiss()
                } label: {
                    Text(primaryActionTitle ?? "Done".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.Theme.primaryBlue))
                        .foregroundStyle(.white)
                }
                .accessibleButton(
                    label: primaryActionTitle ?? "Done".localized,
                    hint: primaryActionTitle == nil ? "Closes this view".localized : "Continues to next screen".localized
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact informational row for embedding where the adult UI shows an upgrade
/// CTA (avatar unlock sheet/popup). Non-interactive by design — it informs, it
/// never routes toward a purchase.
struct ChildPremiumInlineNotice: View {
    var textKey: String = "child_gate.premium.avatar_inline"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.and.child.holdinghands")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityHidden(true)
            Text(textKey.localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Child premium info — trip limit") {
    ChildPremiumInfoView(context: .tripLimit, onDismiss: {})
}

#Preview("Child premium info — saved trips") {
    ChildPremiumInfoView(context: .savedTrips, onDismiss: {})
}

#Preview("Child premium info — onboarding intro") {
    ChildPremiumInfoView(context: .premiumIntro, primaryActionTitle: "Continue".localized, onDismiss: {})
}

#Preview("Child premium inline notice") {
    ChildPremiumInlineNotice()
        .padding()
}
