//
//  DriversLicenseWalletView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 6/19/26.
//

//  A cosmetics catalog and a "locker" screen for browsing / equipping the
//  license skins defined by `LicenseStyle` (see UserDriversLicenseCard.swift).
//
//  Ownership is the host app's data — pass `ownedIDs` and bind `equippedID`.
//  The locker is purely a view over that state; it doesn't persist anything.
//
//      DriversLicenseWalletView(license: me,
//                        ownedIDs: player.ownedCosmeticIDs,
//                        equippedID: $player.equippedCosmeticID) {
//          Image("avatar").resizable().scaledToFill()   // the player's character
//      }
//

import SwiftUI

// MARK: - Rarity

enum LicenseRarity: Int, CaseIterable, Comparable {
    case common, rare, epic, legendary, mythic

    var title: String {
        switch self {
        case .common:    return "Common"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        case .mythic:    return "Mythic"
        }
    }

    var color: Color {
        switch self {
        case .common:    return Color(red: 0.55, green: 0.58, blue: 0.62)
        case .rare:      return Color(red: 0.20, green: 0.62, blue: 0.92)
        case .epic:      return Color(red: 0.60, green: 0.32, blue: 0.86)
        case .legendary: return Color(red: 0.96, green: 0.66, blue: 0.12)
        case .mythic:    return Color(red: 0.95, green: 0.23, blue: 0.46)
        }
    }

    static func < (lhs: LicenseRarity, rhs: LicenseRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Unlock source

enum UnlockSource {
    case starter
    case rankUp(level: Int)
    case seasonPass(String)
    case prestige

    var label: String {
        switch self {
        case .starter:               return "Starter"
        case .rankUp(let level):     return "Rank \(level)"
        case .seasonPass(let name):  return "Season · \(name)"
        case .prestige:              return "Prestige"
        }
    }

    var icon: String {
        switch self {
        case .starter:    return "flag.fill"
        case .rankUp:     return "chevron.up.circle.fill"
        case .seasonPass: return "rosette"
        case .prestige:   return "crown.fill"
        }
    }
}

// MARK: - Catalog entry

struct LicenseCosmetic: Identifiable {
    let id: String
    let name: String
    let style: LicenseStyle
    let rarity: LicenseRarity
    let source: UnlockSource

    init(id: String, name: String, style: LicenseStyle,
         rarity: LicenseRarity, source: UnlockSource) {
        self.id = id
        self.name = name
        self.style = style
        self.rarity = rarity
        self.source = source
    }
}

extension LicenseCosmetic {

    /// The full grantable set. Add rows here as new passes / tiers ship.
    static let catalog: [LicenseCosmetic] = [
        LicenseCosmetic(id: "standard", name: "Standard Issue", style: .standard,
                        rarity: .common, source: .starter),

        LicenseCosmetic(id: "carbon", name: "Carbon Edition", style: .carbonEdition,
                        rarity: .rare, source: .rankUp(level: 10)),
        LicenseCosmetic(id: "summer", name: "Summer Road", style: .summerRoad,
                        rarity: .rare, source: .seasonPass("Summer Road")),
        LicenseCosmetic(id: "emerald", name: "Emerald Trail", style: .emeraldTrail,
                        rarity: .rare, source: .seasonPass("Trailblazer")),

        LicenseCosmetic(id: "winter", name: "Winter Frost", style: .winterFrost,
                        rarity: .epic, source: .seasonPass("Winter Frost")),
        LicenseCosmetic(id: "gold", name: "Gold Foil", style: .goldFoil,
                        rarity: .epic, source: .rankUp(level: 25)),
        LicenseCosmetic(id: "platinum", name: "Platinum Foil", style: .platinumFoil,
                        rarity: .epic, source: .rankUp(level: 40)),

        LicenseCosmetic(id: "midnight", name: "Midnight Drive",
                        style: LicenseStyle(palette: .midnight, finish: .holographic,
                                            trim: .glow,
                                            emblem: LicenseEmblem(symbol: "moon.stars.fill"),
                                            animatedShine: true),
                        rarity: .legendary, source: .rankUp(level: 60)),
        LicenseCosmetic(id: "neon", name: "Neon Nights", style: .neonNights,
                        rarity: .legendary, source: .seasonPass("Neon Nights")),

        LicenseCosmetic(id: "founder", name: "Founder", style: .founder,
                        rarity: .mythic, source: .prestige)
    ]

    static func first(_ id: String) -> LicenseCosmetic {
        catalog.first { $0.id == id } ?? catalog[0]
    }
}

extension LicenseStyle {
    /// A copy with the sweeping shine disabled — for grids / thumbnails where
    /// many simultaneous animations would be wasteful.
    var staticPreview: LicenseStyle {
        var copy = self
        copy.animatedShine = false
        return copy
    }
}

// MARK: - Tile

struct CosmeticTile<Portrait: View>: View {

    let cosmetic: LicenseCosmetic
    let license: UserDriversLicense
    let isOwned: Bool
    let isEquipped: Bool
    var cardWidth: CGFloat = 150
    @ViewBuilder var portrait: () -> Portrait
    let onTap: () -> Void

    private var rarityColor: Color { cosmetic.rarity.color }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 9) {
                ZStack {
                    UserDriversLicenseCard(license: license, width: cardWidth,
                                    style: cosmetic.style.staticPreview) { portrait() }
                        .allowsHitTesting(false)          // tile owns the tap, not the flip
                        .saturation(isOwned ? 1 : 0)
                        .opacity(isOwned ? 1 : 0.5)

                    if !isOwned { lockOverlay }
                }
                .overlay(alignment: .topTrailing) {
                    if isEquipped { equippedCheck.padding(6) }
                }

                VStack(spacing: 3) {
                    Text(cosmetic.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 5) {
                        Circle().fill(rarityColor).frame(width: 7, height: 7)
                        Text(cosmetic.rarity.title.uppercased())
                            .font(.caption2.weight(.bold)).foregroundStyle(rarityColor)
                        if !isOwned {
                            Text("· \(cosmetic.source.label)")
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        } else if isEquipped {
                            Text("· EQUIPPED")
                                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isEquipped ? rarityColor : rarityColor.opacity(0.22),
                              lineWidth: isEquipped ? 2.5 : 1))
            .shadow(color: isEquipped ? rarityColor.opacity(0.45) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cosmetic.name), \(cosmetic.rarity.title)")
        .accessibilityValue(isOwned ? (isEquipped ? "equipped" : "owned")
                                     : "locked, \(cosmetic.source.label)")
    }

    private var lockOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardWidth * 0.05, style: .continuous)
                .fill(.black.opacity(0.28))
            VStack(spacing: 4) {
                Image(systemName: cosmetic.source.icon).font(.system(size: 16, weight: .bold))
                Text(cosmetic.source.label).font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(6)
        }
    }

    private var equippedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(rarityColor, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
    }
}

// MARK: - Wallet screen

struct DriversLicenseWalletView<Portrait: View>: View {

    let license: UserDriversLicense
    var cosmetics: [LicenseCosmetic] = LicenseCosmetic.catalog
    let ownedIDs: Set<String>
    @Binding var equippedID: String
    @ViewBuilder var portrait: () -> Portrait

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unlocked = "Unlocked", locked = "Locked"
        var id: String { rawValue }
    }
    @State private var filter: Filter = .all

    private var equipped: LicenseCosmetic {
        cosmetics.first { $0.id == equippedID } ?? cosmetics[0]
    }

    private var visible: [LicenseCosmetic] {
        cosmetics
            .filter { c in
                switch filter {
                case .all:      return true
                case .unlocked: return ownedIDs.contains(c.id)
                case .locked:   return !ownedIDs.contains(c.id)
                }
            }
            .sorted { lhs, rhs in
                let lo = ownedIDs.contains(lhs.id), ro = ownedIDs.contains(rhs.id)
                if lo != ro { return lo && !ro }                  // owned first
                if lhs.rarity != rhs.rarity { return lhs.rarity > rhs.rarity }
                return lhs.name < rhs.name
            }
    }

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 14)]

    var body: some View {
        GeometryReader { geo in
            let heroWidth = min(geo.size.width - 32, 360)
            ScrollView {
                VStack(spacing: 18) {

                    // Equipped hero — fully interactive (tap to flip).
                    UserDriversLicenseCard(license: license, width: heroWidth, style: equipped.style) {
                        portrait()
                    }
                    .padding(.top, 4)

                    header
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visible) { cosmetic in
                            CosmeticTile(cosmetic: cosmetic,
                                         license: license,
                                         isOwned: ownedIDs.contains(cosmetic.id),
                                         isEquipped: cosmetic.id == equippedID,
                                         portrait: portrait) {
                                guard ownedIDs.contains(cosmetic.id) else { return }
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    equippedID = cosmetic.id
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Wallet").font(.title2.weight(.bold))
                Text(equipped.name)
                    .font(.subheadline).foregroundStyle(equipped.rarity.color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(ownedIDs.count)/\(cosmetics.count)")
                    .font(.title3.weight(.heavy)).foregroundStyle(.primary)
                Text("UNLOCKED")
                    .font(.caption2.weight(.bold)).kerning(0.8).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

private struct DemoAvatar: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.20),
                                    Color(red: 0.90, green: 0.30, blue: 0.45)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { g in
                Image(systemName: "figure.wave")
                    .resizable().scaledToFit()
                    .frame(width: g.size.width * 0.55, height: g.size.height * 0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct LockerDemo: View {
    @State private var equipped = "neon"
    private let owned: Set<String> = ["standard", "carbon", "summer", "winter", "gold", "neon"]
    var body: some View {
        DriversLicenseWalletView(license: .sample, ownedIDs: owned, equippedID: $equipped) {
            PreviewPortrait()
        }
    }
}

#Preview("Locker — Light") { LockerDemo() }

#Preview("Locker — Dark") { LockerDemo().preferredColorScheme(.dark) }
