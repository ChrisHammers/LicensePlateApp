//
//  AchievementListView.swift
//  RoadTrip Royale
//
//  Browse all achievements — unlocked and locked — with status + category
//  filters, progress meters, and how-to-unlock detail.
//
//      AchievementListView(statuses: player.achievementStatuses)
//

import SwiftUI

struct AchievementListView: View {

    var achievements: [Achievement]
    var statuses: [String: AchievementStatus]

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, unlocked, locked
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "achievement.filter.all".localized
            case .unlocked: return "achievement.filter.unlocked".localized
            case .locked: return "achievement.filter.locked".localized
            }
        }
    }

    @State private var statusFilter: StatusFilter = .all
    @State private var category: AchievementCategory? = nil   // nil == all

    private func status(_ a: Achievement) -> AchievementStatus { statuses[a.id] ?? .locked }

    private var unlockedCount: Int { achievements.filter { status($0).isUnlocked }.count }
    private var earnedXP: Int {
        achievements.filter { status($0).isUnlocked }.reduce(0) { $0 + $1.xpReward }
    }

    private var rows: [Achievement] {
        achievements
            .filter { a in
                let s = status(a)
                let statusOK: Bool
                switch statusFilter {
                case .all:      statusOK = true
                case .unlocked: statusOK = s.isUnlocked
                case .locked:   statusOK = !s.isUnlocked
                }
                let catOK = category == nil || a.category == category
                return statusOK && catOK
            }
            .sorted { lhs, rhs in
                let lu = status(lhs).isUnlocked, ru = status(rhs).isUnlocked
                if lu != ru { return lu && !ru }                 // unlocked first
                if lhs.rarity != rhs.rarity { return lhs.rarity > rhs.rarity }
                return lhs.title < rhs.title
            }
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 0) {
                header
                filters
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { AchievementRow(achievement: $0, status: status($0)) }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("achievement.list.title".localized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityAddTraits(.isHeader)
                Text("achievement.list.xp_earned".localized(earnedXP.formatted()))
                    .font(.subheadline).foregroundStyle(Color.Theme.softBrown)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(unlockedCount)/\(achievements.count)")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text("achievement.list.unlocked_label".localized)
                    .font(.caption2.weight(.bold)).kerning(0.8)
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("achievement.filter.status.a11y".localized, selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .tint(Color.Theme.primaryBlue)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil, label: "achievement.filter.all".localized, icon: "square.grid.2x2.fill")
                    ForEach(AchievementCategory.allCases) {
                        categoryChip($0, label: $0.localizedTitle, icon: $0.icon)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 6)
    }

    private func categoryChip(_ value: AchievementCategory?, label: String, icon: String) -> some View {
        let selected = category == value
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { category = value }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.bold))
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.Theme.primaryBlue))
            .background(selected ? AnyShapeStyle(Color.Theme.primaryBlue)
                                 : AnyShapeStyle(Color.Theme.cardBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

struct AchievementRow: View {
    let achievement: Achievement
    let status: AchievementStatus

    private var color: Color { achievement.rarity.color }
    private var unlocked: Bool { status.isUnlocked }
    private var fraction: Double {
        guard achievement.goal > 1 else { return unlocked ? 1 : 0 }
        return min(1, Double(status.progress) / Double(achievement.goal))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(achievement.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer()
                    trailing
                }
                Text(achievement.detail)
                    .font(.caption).foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)

                if !unlocked && achievement.hasMeter { meter }

                HStack(spacing: 6) {
                    tag(achievement.rarity.title.uppercased(), color: color)
                    tag(achievement.category.localizedTitle.uppercased(), color: Color.Theme.softBrown)
                    if unlocked, let date = status.unlockedDate {
                        Text("· " + date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(Color.Theme.softBrown)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(unlocked ? color.opacity(0.45) : Color.Theme.softBrown.opacity(0.2),
                          lineWidth: unlocked ? 1.5 : 1))
        .opacity(unlocked ? 1 : 0.92)
    }

    private var icon: some View {
        Image(systemName: achievement.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .saturation(unlocked ? 1 : 0)
            .opacity(unlocked ? 1 : 0.5)
            .overlay {
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            if achievement.xpReward > 0 {
                Text("achievement.row.xp_reward".localized(achievement.xpReward.formatted()))
                    .font(.caption2.weight(.bold)).foregroundStyle(Color.Theme.softBrown)
            }
            if unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17)).foregroundStyle(color)
            }
        }
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.Theme.softBrown.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("\(min(status.progress, achievement.goal))/\(achievement.goal)")
                .font(.caption2.weight(.semibold)).foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.top, 1)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).kerning(0.4)
            .foregroundStyle(color)
    }
}

// MARK: - Preview

private enum AchievementListPreviewSupport {
    static var sampleAchievements: [Achievement] {
        ProgressionCatalogProjection.achievements(from: .bundledDefault)
    }

    static var sampleStatuses: [String: AchievementStatus] {
        AchievementProgressResolver.statuses(
            for: ProgressionCatalog.bundledDefault.visibleAchievements,
            inputs: AchievementProgressInputs(
                progression: UserProgressionEffectiveTotals(
                    totalXp: 86_400,
                    acceptedRegionFindCount: 48,
                    competitiveFirstPlaceFinishes: 121,
                    everCompetitiveFirstPlace: true,
                    hasPendingLocalProgression: false
                ),
                lifetimeStats: UserLifetimeStats(
                    totalCompletedTrips: 36,
                    totalGamesPlayed: 184,
                    totalDiscoveries: 1_240,
                    totalWeightedScore: 245_980,
                    familyOnlyTripsCount: 0,
                    lastComputedAt: .now
                ),
                isFamilyMember: true,
                isRoyale: true,
                isFounder: false
            )
        )
    }
}

#Preview("Achievements — Light") {
    AchievementListView(
        achievements: AchievementListPreviewSupport.sampleAchievements,
        statuses: AchievementListPreviewSupport.sampleStatuses
    )
}

#Preview("Achievements — Dark") {
    AchievementListView(
        achievements: AchievementListPreviewSupport.sampleAchievements,
        statuses: AchievementListPreviewSupport.sampleStatuses
    )
        .preferredColorScheme(.dark)
}
