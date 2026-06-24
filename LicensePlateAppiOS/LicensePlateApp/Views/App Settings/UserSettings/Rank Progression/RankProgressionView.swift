//
//  RankProgressionView.swift
//  RoadTrip Royale
//
//  Shows the player's current rank, progress to the next, and the full ladder
//  of past and future ranks with the rewards unlocked at each.
//
//      RankProgressionView(xp: player.xp)
//

import SwiftUI

struct RankProgressionView: View {

    var ladder: RankLadder = .standard
    var xp: Int

    private var current: Rank { ladder.currentRank(xp: xp) }
    private var next: Rank? { ladder.nextRank(xp: xp) }

    enum RankState { case achieved, current, locked }
    private func state(for rank: Rank) -> RankState {
        if rank.level == current.level { return .current }
        return rank.xpRequired <= xp ? .achieved : .locked
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(ladder.ranks) { rank in
                            RankNodeRow(rank: rank,
                                        state: state(for: rank),
                                        isFirst: rank.level == ladder.ranks.first?.level,
                                        isLast: rank.level == ladder.ranks.last?.level)
                                .id(rank.level)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.easeInOut) { proxy.scrollTo(current.level, anchor: .center) }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: current.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        LinearGradient(colors: [current.accent, current.accent.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2))
                    .shadow(color: current.accent.opacity(0.5), radius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RANK \(current.level)")
                        .font(.caption.weight(.heavy)).kerning(1).foregroundStyle(current.accent)
                    Text(current.title).font(.title2.weight(.bold))
                }
                Spacer()
            }

            if let next {
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [current.accent, next.accent],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * ladder.progress(xp: xp))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(xp.formatted()) XP")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(max(0, next.xpRequired - xp).formatted()) XP to \(next.title)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Max rank reached")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(current.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}

// MARK: - Node row

struct RankNodeRow: View {
    let rank: Rank
    let state: RankProgressionView.RankState
    let isFirst: Bool
    let isLast: Bool

    private var reached: Bool { state != .locked }
    private var spineColor: Color { rank.accent }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            spine
            card
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spine: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(reached ? spineColor : Color.primary.opacity(0.12))
                .frame(width: 3, height: isFirst ? 0 : 14)
            node
            Rectangle()
                .fill(state == .achieved ? spineColor : Color.primary.opacity(0.12))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 40)
    }

    @ViewBuilder private var node: some View {
        switch state {
        case .achieved:
            circle(fill: rank.accent) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
            }
        case .current:
            circle(fill: rank.accent) {
                Text("\(rank.level)").font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().strokeBorder(rank.accent.opacity(0.4), lineWidth: 4).scaleEffect(1.25))
            .shadow(color: rank.accent.opacity(0.6), radius: 8)
        case .locked:
            circle(fill: Color.primary.opacity(0.12)) {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func circle<Content: View>(fill: some ShapeStyle, @ViewBuilder content: () -> Content) -> some View {
        ZStack { Circle().fill(fill); content() }
            .frame(width: 36, height: 36)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rank.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(reached ? .primary : .secondary)
                    Text(rank.level == 1 ? "Starting rank"
                                         : (reached ? "Reached at \(rank.xpRequired.formatted()) XP"
                                                    : "Requires \(rank.xpRequired.formatted()) XP"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if state == .current {
                    Text("YOU")
                        .font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(rank.accent, in: Capsule())
                }
            }

            ForEach(rank.unlocks) { unlock in
                HStack(spacing: 8) {
                    Image(systemName: unlock.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(reached ? AnyShapeStyle(rank.accent) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .background((reached ? rank.accent : Color.secondary).opacity(0.14), in: Circle())
                    Text(unlock.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(reached ? .primary : .secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(state == .current ? 0.06 : 0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(state == .current ? rank.accent : Color.primary.opacity(0.06),
                          lineWidth: state == .current ? 2 : 1))
    }
}

// MARK: - Preview

#Preview("Ranks — Light") {
    RankProgressionView(xp: UserDriversLicense.sample.xp)   // 86,400 -> Highway Legend, ~90% to next
}

#Preview("Ranks — Dark") {
    RankProgressionView(xp: 12_500).preferredColorScheme(.dark)
}
