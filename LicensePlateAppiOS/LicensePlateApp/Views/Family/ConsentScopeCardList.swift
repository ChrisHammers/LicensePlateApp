//
//  ConsentScopeCardList.swift
//  LicensePlateApp
//
//  COPPA v3 FR-65 / v4 FR-103 (F-21 slice 2): the per-scope consent cards. Render only:
//  which cards exist, their state and every string key come from
//  `ConsentScopeCardPolicy.cards(mode:)`. One view for the approval step and (later) the
//  manage screen, so the wording cannot fork.
//
//  Every string here is VERSIONED CONSENT TEXT (`CONSENT_TEXT_VERSION`); see the note above
//  the family.consent_scope.* keys in Localizable.strings.
//
//  A card's policy link opens `rtr-legal://privacy-children-*` through the environment's
//  `openURL`. The host (`FamilyChildConsentBlock`) intercepts those URLs and presents the
//  Privacy Policy at that subsection; nothing here talks to the system.
//

import SwiftUI

struct ConsentScopeCardList: View {
    let mode: ConsentScopeCardPolicy.Mode

    private var cards: [ConsentScopeCardModel] {
        ConsentScopeCardPolicy.cards(mode: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(cards) { card in
                ConsentScopeCard(card: card)
            }
        }
    }
}

/// One scope. VoiceOver reads it as ONE element: label = the scope name, value = its state,
/// hint = the scope's hint line, a custom action for the policy link, and the detail lines
/// as custom content (the More Content rotor), so nothing on the card is sighted-only.
private struct ConsentScopeCard: View {
    let card: ConsentScopeCardModel

    @Environment(\.openURL) private var openURL

    /// The detail lines in display order; the optional ones only when the card has them.
    private var detailKeys: [String] {
        let optional: [String?] = [card.notificationsKey, card.requiredReasonKey, card.frozenReasonKey]
        return [card.meaningKey, card.collectedKey, card.whoSeesKey] + optional.compactMap { $0 }
    }

    private func openPolicy() {
        guard let url = card.anchor.url else { return }
        openURL(url)
    }

    var body: some View {
        cardContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.nameKey.localized)
            .accessibilityValue(card.accessibilityValueKey.localized)
            .accessibilityHint(card.accessibilityHintKey?.localized ?? "")
            // Double-tap opens the card's subsection too; the element's center is usually a
            // detail line, which does nothing on its own.
            .accessibilityAction { openPolicy() }
            .accessibilityAction(named: Text(ConsentScopeCardPolicy.accessibilityPolicyActionKey.localized)) {
                openPolicy()
            }
            .accessibilityCustomContent(contentKey("meaning"), text(card.meaningKey))
            .accessibilityCustomContent(contentKey("collected"), text(card.collectedKey))
            .accessibilityCustomContent(contentKey("who_sees"), text(card.whoSeesKey))
            .accessibilityCustomContent(contentKey("notifications"), text(card.notificationsKey))
            .accessibilityCustomContent(contentKey("required_reason"), text(card.requiredReasonKey))
            .accessibilityCustomContent(contentKey("frozen_reason"), text(card.frozenReasonKey))
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.nameKey.localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)

            stateRow

            ForEach(detailKeys, id: \.self) { key in
                Text(key.localized)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }

            policyButton
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Theme.primaryBlue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.Theme.primaryBlue.opacity(0.15), lineWidth: 1)
        )
    }

    /// At least 44pt tall at every text size; it grows with Dynamic Type, never clips.
    private var policyButton: some View {
        Button(action: openPolicy) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "doc.text")
                Text(ConsentScopeCardPolicy.policyLinkKey.localized)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(.footnote, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(Color.Theme.primaryBlue)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        // Plain, so inside a List row only this button reacts to its own taps.
        .buttonStyle(.plain)
    }

    private func text(_ key: String?) -> Text? {
        key.map { Text($0.localized) }
    }

    /// A distinct id per line: custom content entries that share a key replace each other.
    private func contentKey(_ id: String) -> AccessibilityCustomContentKey {
        AccessibilityCustomContentKey(Text(card.nameKey.localized), id: id)
    }

    /// Icon AND text for the state, never color alone. Frozen cards add a disabled, off
    /// switch; the core card at approval shows a lock and has no switch at all.
    private var stateRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: card.state.systemImage)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityHidden(true)
            Text(card.stateKey.localized)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if card.showsDisabledSwitch {
                Toggle(isOn: .constant(false)) {
                    Text(card.nameKey.localized)
                }
                .labelsHidden()
                .disabled(true)
            }
        }
    }
}

// MARK: - Previews

#Preview("Approval — join") {
    ScrollView {
        ConsentScopeCardList(mode: .approval(kind: .join))
            .padding()
    }
}

#Preview("Approval — Mark as a child") {
    ScrollView {
        ConsentScopeCardList(mode: .approval(kind: .memberFlag))
            .padding()
    }
}

#Preview("Approval — largest text") {
    ScrollView {
        ConsentScopeCardList(mode: .approval(kind: .join))
            .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Approval — dark") {
    ScrollView {
        ConsentScopeCardList(mode: .approval(kind: .memberFlag))
            .padding()
    }
    .background(Color.Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Manage — live", traits: .fixedLayout(width: 820, height: 1180)) {
    ScrollView {
        ConsentScopeCardList(
            mode: .manage(
                status: .live,
                currentScopes: [
                    "core": .granted,
                    "analytics_internal": .unavailable,
                    "ads_child_directed": .unavailable,
                    "location_family_shared": .unavailable,
                    "cross_family_visibility": .unavailable
                ]
            )
        )
        .padding()
    }
}
