//
//  UnlockPopup.swift
//  RoadTrip Royale
//
//  A celebratory popup for rank-ups, achievements, and unlocks, plus a small
//  presenter that queues events so several can play back-to-back.
//
//  Attach the host once near the root:
//
//      RootView()
//          .rewardPopupHost(RewardPresenter.shared)
//
//  Then fire events whenever they happen:
//
//      rewards.show(.rankUp(ladder.currentRank(xp: newXP)))
//      rewards.show(.achievement(unlocked))
//      rewards.show(.cosmetic(cosmetic))     // from LicenseCosmetic
//

import SwiftUI
import Combine

// MARK: - Event

enum RewardEvent: Identifiable {
    case rankUp(Rank)
    case achievement(Achievement)
    case unlock(title: String, detail: String, icon: String, rarity: LicenseRarity)

    var id: String {
        switch self {
        case .rankUp(let r):       return "rank-\(r.level)"
        case .achievement(let a):  return "ach-\(a.id)"
        case .unlock(let t, _, _, _): return "unlock-\(t)"
        }
    }

    /// Convenience bridge from the cosmetics catalog.
    static func cosmetic(_ c: LicenseCosmetic) -> RewardEvent {
        .unlock(title: c.name, detail: "New license skin unlocked.",
                icon: c.source.icon, rarity: c.rarity)
    }

    var kicker: String {
        switch self {
        case .rankUp: return "reward.popup.kicker.rank_up".localized
        case .achievement: return "reward.popup.kicker.achievement".localized
        case .unlock: return "reward.popup.kicker.unlock".localized
        }
    }

    var title: String {
        switch self {
        case .rankUp(let r):      return r.title
        case .achievement(let a): return a.title
        case .unlock(let t, _, _, _): return t
        }
    }

    var detail: String {
        switch self {
        case .rankUp(let r):
            let names = r.unlocks.map(\.title)
            if names.isEmpty {
                return "reward.popup.rank_up.detail".localized(r.level)
            }
            return "reward.popup.rank_up.detail_unlocks".localized(r.level, names.joined(separator: ", "))
        case .achievement(let a): return a.detail
        case .unlock(_, let d, _, _): return d
        }
    }

    var icon: String {
        switch self {
        case .rankUp(let r):      return r.icon
        case .achievement(let a): return a.icon
        case .unlock(_, _, let i, _): return i
        }
    }

    var color: Color {
        switch self {
        case .rankUp(let r):      return r.accent
        case .achievement(let a): return a.rarity.color
        case .unlock(_, _, _, let r): return r.color
        }
    }

    var xpReward: Int? {
        if case .achievement(let a) = self, a.xpReward > 0 { return a.xpReward }
        return nil
    }
}

// MARK: - Presenter (queue)

@MainActor
final class RewardPresenter: ObservableObject {

    static let shared = RewardPresenter()

    @Published private(set) var current: RewardEvent?
    private var queue: [RewardEvent] = []

    func show(_ event: RewardEvent) {
        if current?.id == event.id { return }
        if queue.contains(where: { $0.id == event.id }) { return }
        queue.append(event)
        presentNext()
    }

    func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { current = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.presentNext()
        }
    }

    func reset() {
        queue.removeAll()
        current = nil
    }

    private func presentNext() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { current = next }
    }
}

// MARK: - Host modifier

extension View {
    func rewardPopupHost(_ presenter: RewardPresenter) -> some View {
        modifier(RewardPopupHost(presenter: presenter))
    }
}

struct RewardPopupHost: ViewModifier {
    @ObservedObject var presenter: RewardPresenter

    func body(content: Content) -> some View {
        content.overlay {
            if let event = presenter.current {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { presenter.dismiss() }
                    RewardPopupView(event: event) { presenter.dismiss() }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Popup view

struct RewardPopupView: View {
    let event: RewardEvent
    var onDismiss: () -> Void

    @State private var badgePopped = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RayBurst(color: event.color)
                    .frame(width: 168, height: 168)
                Image(systemName: event.icon)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 92)
                    .background(
                        Circle().fill(LinearGradient(colors: [event.color, event.color.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
                    .shadow(color: event.color.opacity(0.6), radius: 18)
                    .scaleEffect(badgePopped ? 1 : 0.4)
            }
            .padding(.top, 6)

            Text(event.kicker)
                .font(.caption.weight(.heavy)).kerning(1.5)
                .foregroundStyle(event.color)

            Text(event.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(event.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let xp = event.xpReward {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                    Text("reward.popup.xp_bonus".localized(xp.formatted()))
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(event.color)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(event.color.opacity(0.15), in: Capsule())
            }

            Button(action: onDismiss) {
                Text("reward.popup.continue".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(event.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(event.color.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .padding(28)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.06)) {
                badgePopped = true
            }
        }
    }
}

/// A slow-rotating ray burst behind the badge.
private struct RayBurst: View {
    let color: Color
    @State private var spin = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.45))
                    .frame(width: 4, height: 64)
                    .offset(y: -42)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
        .mask(RadialGradient(colors: [.white, .white.opacity(0.0)],
                             center: .center, startRadius: 12, endRadius: 84))
        .onAppear {
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

// MARK: - Preview

private struct PopupDemo: View {
    @StateObject private var rewards = RewardPresenter()
    var body: some View {
        VStack(spacing: 14) {
            Button("Rank Up") {
                rewards.show(.rankUp(ProgressionCatalogProjection.rankLadder(from: .bundledDefault).ranks[6]))
            }
            Button("Achievement") {
                let achievements = ProgressionCatalogProjection.achievements(from: .bundledDefault)
                if let coastToCoast = achievements.first(where: { $0.id == "coast_to_coast" }) {
                    rewards.show(.achievement(coastToCoast))
                }
            }
            Button("Unlock")     { rewards.show(.unlock(title: "Gold Foil",
                                                        detail: "New license skin unlocked.",
                                                        icon: "sparkles", rarity: .epic)) }
            Button("Queue all 3") {
                let ladder = ProgressionCatalogProjection.rankLadder(from: .bundledDefault)
                rewards.show(.rankUp(ladder.ranks[6]))
                if let achievement = ProgressionCatalogProjection.achievements(from: .bundledDefault)
                    .first(where: { $0.id == "coast_to_coast" }) {
                    rewards.show(.achievement(achievement))
                }
                rewards.show(.unlock(title: "Gold Foil", detail: "New license skin unlocked.",
                                     icon: "sparkles", rarity: .epic))
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.5).opacity(0.15))
        .rewardPopupHost(rewards)
    }
}

#Preview("Reward Popup") { PopupDemo() }
