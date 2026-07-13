//
//  AvatarStackView.swift
//  LicensePlateApp
//
//  Stacked avatars (e.g. who found a state); first on top, others greyed; tap opens list.
//

import SwiftUI

struct AvatarStackView: View {
    struct AvatarEntry: Identifiable, Equatable {
        var id: String
        var avatarId: String?
        var legacyFallbackImageName: String?
        var displayName: String
    }

    private let entries: [AvatarEntry]
    let maxDisplay: Int
    let avatarSize: CGFloat
    let overlapRatio: CGFloat
    let overflowCount: Int
    let accessibilityLabel: String?
    let onTap: (() -> Void)?

    init(
        users: [AppUser],
        maxDisplay: Int = 3,
        avatarSize: CGFloat = 32,
        overlapRatio: CGFloat = 0.35,
        accessibilityLabel: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.entries = users.map {
            AvatarEntry(
                id: $0.id,
                avatarId: $0.avatarId,
                legacyFallbackImageName: nil,
                displayName: $0.userName
            )
        }
        self.maxDisplay = maxDisplay
        self.avatarSize = avatarSize
        self.overlapRatio = overlapRatio
        self.overflowCount = max(0, users.count - maxDisplay)
        self.accessibilityLabel = accessibilityLabel
        self.onTap = onTap
    }

    init(
        entries: [AvatarEntry],
        maxDisplay: Int = 3,
        avatarSize: CGFloat = 32,
        overlapRatio: CGFloat = 0.35,
        accessibilityLabel: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.entries = entries
        self.maxDisplay = maxDisplay
        self.avatarSize = avatarSize
        self.overlapRatio = overlapRatio
        self.overflowCount = max(0, entries.count - maxDisplay)
        self.accessibilityLabel = accessibilityLabel
        self.onTap = onTap
    }

    private var displayedEntries: [AvatarEntry] {
        Array(entries.prefix(maxDisplay))
    }

    var body: some View {
        HStack(spacing: -avatarSize * overlapRatio) {
            ForEach(Array(displayedEntries.enumerated()), id: \.element.id) { index, entry in
                avatarBubble(for: entry, index: index)
            }
            if overflowCount > 0 {
                overflowBubble
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "finder.stack.accessibility.default".localized)
        .accessibilityValue(overflowCount > 0 ? "finder.stack.accessibility.overflow".localized(overflowCount) : "")
        .accessibilityAddTraits(onTap == nil ? .isStaticText : .isButton)
    }

    private func handleTap() {
        guard let onTap else { return }
        onTap()
    }

    @ViewBuilder
    private func avatarBubble(for entry: AvatarEntry, index: Int) -> some View {
        AvatarImageView(
            avatarId: entry.avatarId,
            size: avatarSize,
            showRing: true,
            legacyFallbackImageName: entry.legacyFallbackImageName
        )
        .overlay(
            Circle()
                .stroke(Color.Theme.background, lineWidth: 1.5)
        )
        .opacity(index == 0 ? 1.0 : 0.8)
        .zIndex(Double(displayedEntries.count - index))
    }

    private var overflowBubble: some View {
        Text("+\(overflowCount)")
            .font(.system(size: max(10, avatarSize * 0.42), weight: .semibold, design: .rounded))
            .foregroundStyle(Color.Theme.primaryBlue)
            .frame(width: avatarSize, height: avatarSize)
            .background(
                Circle()
                    .fill(Color.Theme.cardBackground)
            )
            .overlay(
                Circle()
                    .stroke(Color.Theme.background, lineWidth: 1.5)
            )
            .zIndex(0)
    }
}

#Preview {
    let u1 = AppUser(userName: "A", avatarId: "navigator_raccoon")
    let u2 = AppUser(userName: "B", avatarId: "scout_otter")
    return AvatarStackView(users: [u1, u2], maxDisplay: 3, avatarSize: 36)
        .padding()
}
