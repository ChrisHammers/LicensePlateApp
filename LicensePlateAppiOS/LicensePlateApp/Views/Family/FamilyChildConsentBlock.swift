//
//  FamilyChildConsentBlock.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-1/FR-2/FR-31): the parental-consent capture shown wherever a manager
//  marks someone as a child — the approval flow (`FamilyPendingApprovals`) and the
//  post-hoc control (`FamilySettings`). ONE block so the wording, the acknowledgment
//  pair, and the affirmation sentence can never drift between the two surfaces.
//
//  This view renders and reports; it holds no rules. The owning view model decides
//  whether the declaration is complete (`ChildApprovalPolicy` / `ChildConsentDraft`),
//  and the server re-checks both acknowledgments regardless.
//
//  The guardian affirmation sentence is CONSENT EVIDENCE. Its wording is versioned
//  server-side (`AFFIRMATION_VERSION` in `childAccountCore.ts`); any edit to
//  `family.child.guardian_affirmation` in ANY locale must bump that constant in the
//  same commit.
//

import SwiftUI

struct FamilyChildConsentBlock: View {
    let draft: ChildConsentDraft
    let yearOptions: [Int]
    let onConsentAcknowledgedChange: (Bool) -> Void
    let onGuardianAffirmedChange: (Bool) -> Void
    let onExpectedAgeOutYearChange: (Int?) -> Void

    /// The document a parent tapped through to, presented over this block so consent is
    /// never abandoned to go read it.
    @State private var presentedPolicyLink: ChildConsentPolicyLink?

    /// The policy summary with its two citations rendered as links. The markdown is
    /// parsed at runtime (the string is already localized, so `LocalizedStringKey`'s
    /// markdown handling is not usable here); a malformed translation degrades to plain
    /// text rather than losing the copy.
    private var policySummary: AttributedString {
        let raw = "family.child.policy_summary".localized
        return (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("family.child.consent_section_title".localized)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibleHeader("family.child.consent_section_title".localized)

            Text(policySummary)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .tint(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint("family.child.policy_links_hint".localized)

            ChildConsentCheckbox(
                title: "family.child.consent_ack".localized,
                isOn: draft.consentAcknowledged,
                accessibilityHint: "family.child.consent_ack_hint".localized,
                onChange: onConsentAcknowledgedChange
            )

            ChildConsentCheckbox(
                title: "family.child.guardian_affirmation".localized,
                isOn: draft.guardianAffirmed,
                accessibilityHint: "family.child.guardian_affirmation_hint".localized,
                onChange: onGuardianAffirmedChange
            )

            VStack(alignment: .leading, spacing: 4) {
                Picker(
                    "family.child.age_out_label".localized,
                    selection: Binding(
                        get: { draft.expectedAgeOutYear },
                        set: { onExpectedAgeOutYearChange($0) }
                    )
                ) {
                    Text("family.child.age_out_none".localized).tag(Int?.none)
                    ForEach(yearOptions, id: \.self) { year in
                        Text(verbatim: String(year)).tag(Int?.some(year))
                    }
                }
                .font(.system(.footnote, design: .rounded))
                .accessibilityLabel("family.child.age_out_label".localized)
                .accessibilityValue(
                    draft.expectedAgeOutYear.map { String($0) } ?? "family.child.age_out_none".localized
                )
                .accessibilityHint("family.child.age_out_hint".localized)

                Text("family.child.age_out_hint".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        // Intercept our own citation links; anything else goes to the system unchanged.
        .environment(\.openURL, OpenURLAction { url in
            guard let link = ChildConsentPolicyLink.from(url: url) else { return .systemAction }
            presentedPolicyLink = link
            return .handled
        })
        .sheet(item: $presentedPolicyLink) { link in
            // Same presentation the onboarding disclaimer uses; the documents own their
            // own Done button and dismiss themselves.
            NavigationStack {
                switch link {
                case .termsOfService:
                    TermsView(scrollToSectionTitle: TermsView.childEligibilitySectionTitle)
                case .privacyPolicy:
                    PrivacyView(scrollToSectionTitle: PrivacyView.childrenSectionTitle)
                }
            }
        }
    }
}

/// Checkbox row: icon + text, tappable as one control, state exposed to VoiceOver as a
/// value (never color alone).
private struct ChildConsentCheckbox: View {
    let title: String
    let isOn: Bool
    let accessibilityHint: String
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                Text(title)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "family.child.a11y.checked".localized : "family.child.a11y.unchecked".localized)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Consent block — empty") {
    FamilyChildConsentBlock(
        draft: ChildConsentDraft(),
        yearOptions: Array(2026...2039),
        onConsentAcknowledgedChange: { _ in },
        onGuardianAffirmedChange: { _ in },
        onExpectedAgeOutYearChange: { _ in }
    )
    .padding()
}

#Preview("Consent block — complete, dark") {
    FamilyChildConsentBlock(
        draft: ChildConsentDraft(
            consentAcknowledged: true,
            guardianAffirmed: true,
            expectedAgeOutYear: 2031
        ),
        yearOptions: Array(2026...2039),
        onConsentAcknowledgedChange: { _ in },
        onGuardianAffirmedChange: { _ in },
        onExpectedAgeOutYearChange: { _ in }
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Consent block — accessibility text size") {
    ScrollView {
        FamilyChildConsentBlock(
            draft: ChildConsentDraft(consentAcknowledged: true),
            yearOptions: Array(2026...2039),
            onConsentAcknowledgedChange: { _ in },
            onGuardianAffirmedChange: { _ in },
            onExpectedAgeOutYearChange: { _ in }
        )
        .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
