//
//  UserDriversLicenseCard.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 6/17/26.
//
//  A self-contained, reusable flip license card. Front = identity,
//  back = full travel record. Tap to flip.
//
//  Cosmetics are layered on via `LicenseStyle` — a lightweight set of
//  finish/trim/emblem/stamp options you can grant as SEASON PASS or
//  RANK-UP rewards. The data and layout never change; only the look does,
//  so every unlock is a "minor change."
//
//  Built entirely from SF Symbols, shapes, and a caller-supplied character
//  image — no baked-in image assets, so the SAME view adapts to light and
//  dark mode through semantic colors.
//
//  Sizing is driven by a single `width`; everything inside scales off it.
//
//  Granting a cosmetic:
//
//      UserDriversLicenseCard(license: me, width: 340,
//                      style: .neonNights,          // a season-pass skin
//                      characterImage: Image("avatar"))
//
//      UserDriversLicenseCard(license: me, width: 340,
//                      style: .rankUp(level: 50),   // a rank-up stamp
//                      characterImage: Image("avatar"))
//
//  Built-in presets:
//      .standard  .carbonEdition  .goldFoil  .platinumFoil  .founder
//      .neonNights  .summerRoad  .winterFrost  .emeraldTrail
//      .rankUp(level:)            // rank-up reward
//      .seasonPass(_:palette:)    // season-pass reward builder
//

import SwiftUI

// MARK: - Badge

struct LicenseBadge: Identifiable {
    let id = UUID()
    var symbol: String
    var label: String
    var color: Color

    init(symbol: String, label: String, color: Color) {
        self.symbol = symbol
        self.label = label
        self.color = color
    }
}

// MARK: - Cosmetic customization (season-pass / rank-up rewards)

/// A seasonal color theme. Overrides the default class-based accent.
struct LicensePalette {
    var name: String
    var accent: Color
    var headerColors: [Color]

    static let neonNights = LicensePalette(
        name: "Neon Nights",
        accent: Color(red: 0.93, green: 0.18, blue: 0.62),
        headerColors: [Color(red: 0.93, green: 0.18, blue: 0.62),
                       Color(red: 0.45, green: 0.18, blue: 0.85)])

    static let summerRoad = LicensePalette(
        name: "Summer Road",
        accent: Color(red: 0.96, green: 0.55, blue: 0.12),
        headerColors: [Color(red: 1.00, green: 0.62, blue: 0.20),
                       Color(red: 0.95, green: 0.34, blue: 0.44)])

    static let winterFrost = LicensePalette(
        name: "Winter Frost",
        accent: Color(red: 0.30, green: 0.68, blue: 0.95),
        headerColors: [Color(red: 0.55, green: 0.83, blue: 1.00),
                       Color(red: 0.28, green: 0.52, blue: 0.85)])

    static let emeraldTrail = LicensePalette(
        name: "Emerald Trail",
        accent: Color(red: 0.10, green: 0.65, blue: 0.42),
        headerColors: [Color(red: 0.16, green: 0.72, blue: 0.50),
                       Color(red: 0.06, green: 0.45, blue: 0.40)])

    static let midnight = LicensePalette(
        name: "Midnight Drive",
        accent: Color(red: 0.40, green: 0.46, blue: 0.95),
        headerColors: [Color(red: 0.28, green: 0.30, blue: 0.62),
                       Color(red: 0.12, green: 0.13, blue: 0.30)])
}

/// Surface finish.
enum LicenseFinish {
    case matte
    case holographic
    case foil(metal: Color)
    case carbon
}

/// Border treatment. (Enums without associated values are implicitly Equatable.)
enum LicenseTrim {
    case standard
    case glow
    case double
    case dashed
}

/// The faint emblem watermarked behind the card.
struct LicenseEmblem {
    var symbol: String
    init(symbol: String = "map.fill") { self.symbol = symbol }
}

/// An optional stamped seal (great for rank-up / season markers).
struct LicenseStamp {
    var text: String
    var symbol: String
    var color: Color?     // nil -> use the card's accent
}

/// The full cosmetic package granted to a player.
struct LicenseStyle {
    var palette: LicensePalette?
    var finish: LicenseFinish
    var trim: LicenseTrim
    var emblem: LicenseEmblem
    var stamp: LicenseStamp?
    var animatedShine: Bool

    init(palette: LicensePalette? = nil,
         finish: LicenseFinish = .matte,
         trim: LicenseTrim = .standard,
         emblem: LicenseEmblem = LicenseEmblem(),
         stamp: LicenseStamp? = nil,
         animatedShine: Bool = false) {
        self.palette = palette
        self.finish = finish
        self.trim = trim
        self.emblem = emblem
        self.stamp = stamp
        self.animatedShine = animatedShine
    }
}

extension LicenseStyle {

    private static let gold = Color(red: 0.83, green: 0.63, blue: 0.12)
    private static let platinum = Color(red: 0.72, green: 0.74, blue: 0.78)

    /// Default look.
    static let standard = LicenseStyle()

    /// Rank-up tier: matte carbon weave.
    static let carbonEdition = LicenseStyle(finish: .carbon,
                                            emblem: LicenseEmblem(symbol: "road.lanes"))

    /// Rank-up tier: gold foil with a double trim and a sweeping shine.
    static let goldFoil = LicenseStyle(finish: .foil(metal: gold),
                                       trim: .double, animatedShine: true)

    /// Rank-up tier: cooler platinum foil.
    static let platinumFoil = LicenseStyle(finish: .foil(metal: platinum),
                                           trim: .double, animatedShine: true)

    /// Prestige reward: gold foil, glow trim, crown emblem, FOUNDER stamp.
    static let founder = LicenseStyle(
        finish: .foil(metal: gold),
        trim: .glow,
        emblem: LicenseEmblem(symbol: "crown.fill"),
        stamp: LicenseStamp(text: "FOUNDER", symbol: "crown.fill", color: gold),
        animatedShine: true)

    /// Season pass: Neon Nights (holographic).
    static let neonNights = LicenseStyle(palette: .neonNights, finish: .holographic,
                                         trim: .glow, emblem: LicenseEmblem(symbol: "bolt.fill"),
                                         animatedShine: true)

    /// Season pass: Summer Road.
    static let summerRoad = LicenseStyle(palette: .summerRoad, finish: .holographic,
                                         emblem: LicenseEmblem(symbol: "sun.max.fill"))

    /// Season pass: Winter Frost (holographic, double trim).
    static let winterFrost = LicenseStyle(palette: .winterFrost, finish: .holographic,
                                          trim: .double, emblem: LicenseEmblem(symbol: "snowflake"))

    /// Season pass: Emerald Trail (dashed trim).
    static let emeraldTrail = LicenseStyle(palette: .emeraldTrail, trim: .dashed,
                                           emblem: LicenseEmblem(symbol: "leaf.fill"))

    /// Rank-up reward: stamps the achieved level onto the card.
    static func rankUp(level: Int, palette: LicensePalette? = nil) -> LicenseStyle {
        LicenseStyle(palette: palette, trim: .glow,
                     stamp: LicenseStamp(text: "LV \(level)",
                                         symbol: "chevron.up.circle.fill", color: nil))
    }

    /// Season-pass reward builder — name it, color it, ship it.
    static func seasonPass(_ name: String, palette: LicensePalette,
                           holographic: Bool = true) -> LicenseStyle {
        LicenseStyle(palette: palette,
                     finish: holographic ? .holographic : .matte,
                     trim: .glow,
                     stamp: LicenseStamp(text: name.uppercased(), symbol: "rosette", color: nil),
                     animatedShine: holographic)
    }
}

// MARK: - Model

struct UserDriversLicense {

    var holderName: String
    var issueDate: Date
    var rankLevel: Int
    var rankTitle: String

    var statesProvincesFound: Int
    var totalStatesProvinces: Int
    var platesFound: Int

    var tripsTaken: Int
    var gamesPlayed: Int
    var gamesWon: Int
    var xp: Int
    var score: Int

    var isRoyale: Bool
    var isFamilyMember: Bool
    var badges: [LicenseBadge]

    var licenseNumber: String?

    init(holderName: String,
         issueDate: Date,
         rankLevel: Int,
         rankTitle: String,
         statesProvincesFound: Int,
         totalStatesProvinces: Int = 101,
         platesFound: Int,
         tripsTaken: Int,
         gamesPlayed: Int,
         gamesWon: Int,
         xp: Int,
         score: Int,
         isRoyale: Bool = false,
         isFamilyMember: Bool = false,
         badges: [LicenseBadge] = [],
         licenseNumber: String? = nil) {
        self.holderName = holderName
        self.issueDate = issueDate
        self.rankLevel = rankLevel
        self.rankTitle = rankTitle
        self.statesProvincesFound = statesProvincesFound
        self.totalStatesProvinces = totalStatesProvinces
        self.platesFound = platesFound
        self.tripsTaken = tripsTaken
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.xp = xp
        self.score = score
        self.isRoyale = isRoyale
        self.isFamilyMember = isFamilyMember
        self.badges = badges
        self.licenseNumber = licenseNumber
    }
}

extension UserDriversLicense {

    var completion: Double {
        guard totalStatesProvinces > 0 else { return 0 }
        return min(1, max(0, Double(statesProvincesFound) / Double(totalStatesProvinces)))
    }

    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }

    var winRateText: String {
        gamesPlayed > 0 ? "\(Int((winRate * 100).rounded()))% win" : "—"
    }

    var licenseClass: String {
        switch completion {
        case 1.0:     return "S"
        case 0.75...: return "A"
        case 0.45...: return "B"
        case 0.20...: return "C"
        default:      return "D"
        }
    }

    /// Default accent when no palette is granted.
    var accent: Color {
        if isRoyale { return Color(red: 0.82, green: 0.62, blue: 0.11) }
        switch licenseClass {
        case "S": return Color(red: 0.62, green: 0.30, blue: 0.78)
        case "A": return Color(red: 0.16, green: 0.52, blue: 0.90)
        case "B": return Color(red: 0.13, green: 0.60, blue: 0.53)
        case "C": return Color(red: 0.42, green: 0.47, blue: 0.60)
        default:  return Color(red: 0.50, green: 0.53, blue: 0.58)
        }
    }

    var resolvedLicenseNumber: String {
        if let licenseNumber, !licenseNumber.isEmpty { return licenseNumber }
        var hash: UInt64 = 2166136261
        let seed = holderName + "\(Int(issueDate.timeIntervalSince1970))"
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 16777619 }
        let digits = String(format: "%011llu", hash % 100_000_000_000)
        let a = digits.prefix(2)
        let b = digits.dropFirst(2).prefix(5)
        let c = digits.dropFirst(7).prefix(4)
        return "RR-\(a)\(b)-\(c)"
    }

    static var sample: UserDriversLicense {
        previewSample(isRoyale: true, isFamilyMember: true)
    }

    /// Shared preview factory. Completion drives `licenseClass` / default accent when no palette.
    /// Thresholds: D under 20%, C 20%+, B 45%+, A 75%+, S 100%.
    static func previewSample(
        statesProvincesFound: Int = 48,
        totalStatesProvinces: Int = 101,
        isRoyale: Bool = false,
        isFamilyMember: Bool = false,
        includeBadges: Bool = true
    ) -> UserDriversLicense {
        UserDriversLicense(
            holderName: "Chris Hammers",
            issueDate: Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 9)) ?? .now,
            rankLevel: 27,
            rankTitle: "Highway Legend",
            statesProvincesFound: statesProvincesFound,
            totalStatesProvinces: totalStatesProvinces,
            platesFound: 1240,
            tripsTaken: 36,
            gamesPlayed: 184,
            gamesWon: 121,
            xp: 86_400,
            score: 245_980,
            isRoyale: isRoyale,
            isFamilyMember: isFamilyMember,
            badges: includeBadges ? previewBadges : []
        )
    }

    /// Non-Royale card for each class letter (default accent / header when style has no palette).
    static func sampleForClass(_ licenseClass: String) -> UserDriversLicense {
        let found: Int
        switch licenseClass.uppercased() {
        case "S": found = 101
        case "A": found = 80
        case "B": found = 50
        case "C": found = 25
        default:  found = 10
        }
        return previewSample(statesProvincesFound: found, isRoyale: false, isFamilyMember: false)
    }

    private static let previewBadges: [LicenseBadge] = [
        LicenseBadge(symbol: "flame.fill",          label: "Hot Streak",    color: .orange),
        LicenseBadge(symbol: "bolt.fill",           label: "Speed Spotter", color: .yellow),
        LicenseBadge(symbol: "star.fill",           label: "All-Star",      color: .blue),
        LicenseBadge(symbol: "map.fill",            label: "Explorer",      color: .green),
        LicenseBadge(symbol: "crown.fill",          label: "Champion",      color: .purple),
        LicenseBadge(symbol: "checkmark.seal.fill", label: "Verified",      color: .teal)
    ]
}

// MARK: - Portrait helpers

struct LicenseImagePortrait: View {
    let image: Image
    var body: some View { image.resizable().scaledToFill() }
}

struct LicensePortraitPlaceholder: View {
    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - View

struct UserDriversLicenseCard<Portrait: View>: View {

    let license: UserDriversLicense
    var width: CGFloat
    var style: LicenseStyle
    private let portrait: Portrait

    init(license: UserDriversLicense,
         width: CGFloat = 360,
         style: LicenseStyle = .standard,
         @ViewBuilder portrait: () -> Portrait) {
        self.license = license
        self.width = width
        self.style = style
        self.portrait = portrait()
    }

    private let aspectRatio: CGFloat = 1.586
    private let baseWidth: CGFloat = 360

    @Environment(\.colorScheme) private var scheme
    @State private var flipped = false
    @State private var shinePhase: CGFloat = 0
    
    // Optional caller-supplied accessory (edit / share / etc.). Set via
    // `.accessory { ... }`. Stored type-erased so the convenience initializers
    // don't need a second generic parameter.
    private var accessoryContent: AnyView? = nil
    private var accessoryAlignment: Alignment = .topTrailing
    private var accessoryVisibleOnBack: Bool = false

    private var height: CGFloat { width / aspectRatio }
    private var s: CGFloat { width / baseWidth }
    private var corner: CGFloat { 18 * s }

    /// Granted palette overrides the default class/Royale accent.
    private var accent: Color { style.palette?.accent ?? license.accent }

    var body: some View {
        ZStack {
            cardBackground
            watermark
            materialOverlay                       // carbon weave sits under content
            frontSide.opacity(flipped ? 0 : 1)
            backSide
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            sheenOverlay                          // holo / foil sheen over content
            if style.animatedShine { animatedShine }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(trimOverlay)
        .overlay(alignment: accessoryAlignment) { accessoryOverlay }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.18), radius: 14 * s, x: 0, y: 7 * s)
        .shadow(color: glowColor, radius: 14 * s)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { flipped.toggle() }
        }
        .onAppear {
            guard style.animatedShine else { return }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) { shinePhase = 1 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(license.holderName), RoadTrip Royale license. Double tap to flip.")
    }
    
    // MARK: Accessory slot

        /// Sits above the card, outside the clip so it never gets corner-cut.
        /// It's part of the view tree that owns the flip `onTapGesture`, so any
        /// control inside (Button, Menu) takes tap priority over the flip — the
        /// rest of the card still flips. Hidden + inert on the back unless asked.
        @ViewBuilder private var accessoryOverlay: some View {
            if let accessoryContent {
                let visible = accessoryVisibleOnBack || !flipped
                accessoryContent
                    .padding(8 * s)
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .animation(.easeInOut(duration: 0.2), value: visible)
            }
        }

        /// Attach a control (edit, share, set-active, a Menu, anything) to a corner
        /// of the card. The card handles placement, the flip-safe hit testing, and
        /// hiding it on the back.
        ///
        ///     UserDriversLicenseCard(license: me, style: skin, characterImage: avatar)
        ///         .accessory { LicenseCornerButton(systemImage: "pencil") { edit() } }
        ///
        func accessory<Content: View>(alignment: Alignment = .topTrailing,
                                      visibleOnBack: Bool = false,
                                      @ViewBuilder content: () -> Content) -> Self {
            var copy = self
            copy.accessoryContent = AnyView(content())
            copy.accessoryAlignment = alignment
            copy.accessoryVisibleOnBack = visibleOnBack
            return copy
        }

    // MARK: Front

    private var frontSide: some View {
        ZStack(alignment: .bottomTrailing) {
            if let stamp = style.stamp { stampView(stamp).allowsHitTesting(false) }   // behind content
            VStack(spacing: 0) {
                frontHeader
                HStack(alignment: .top, spacing: 13 * s) {
                    portraitView
                    frontFields
                }
                .padding(.horizontal, 15 * s)
                .padding(.top, 11 * s)
                Spacer(minLength: 0)
                frontFooter
                    .padding(.horizontal, 15 * s)
                    .padding(.bottom, 10 * s)
            }
        }
    }

    private var frontHeader: some View {
        HStack(spacing: 9 * s) {
            Image(systemName: "car.fill").font(.system(size: 19 * s, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("RoadTrip Royale")
                    .font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                Text("OFFICIAL TRAVELER LICENSE")
                    .font(.system(size: 7.5 * s, weight: .semibold)).kerning(1.4 * s).opacity(0.9)
            }
            Spacer(minLength: 0)
            classBadge
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15 * s)
        .padding(.vertical, 9 * s)
        .background(headerGradient)
    }

    private var classBadge: some View {
        VStack(spacing: 0) {
            if license.isRoyale {
                Image(systemName: "crown.fill").font(.system(size: 8 * s, weight: .bold))
            } else {
                Text("CLASS").font(.system(size: 6 * s, weight: .bold)).kerning(1 * s)
            }
            Text(license.licenseClass).font(.system(size: 17 * s, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: 36 * s, height: 36 * s)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
            .strokeBorder(.white.opacity(0.5), lineWidth: 1 * s))
    }

    private var portraitView: some View {
        VStack(spacing: 5 * s) {
            portrait
                .frame(width: 78 * s, height: 96 * s)
                .clipShape(RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                    .strokeBorder(accent.opacity(0.6), lineWidth: 1.5 * s))
                .overlay(alignment: .bottom) {
                    Text("LV \(license.rankLevel)")
                        .font(.system(size: 9 * s, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7 * s).padding(.vertical, 2 * s)
                        .background(accent, in: Capsule())
                        .offset(y: 7 * s)
                }
            Text(license.rankTitle.uppercased())
                .font(.system(size: 8.5 * s, weight: .heavy, design: .rounded)).kerning(0.3 * s)
                .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.5)
                .padding(.top, 4 * s)
        }
        .frame(width: 82 * s)
    }

    private var frontFields: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            field("HOLDER", license.holderName)
            HStack(alignment: .top, spacing: 10 * s) {
                miniStat("SCORE", license.score.formatted())
                miniStat("XP", license.xp.formatted())
            }
            statesProgress
            HStack(spacing: 6 * s) {
                if license.isRoyale { chip("ROYALE", system: "crown.fill", filled: true) }
                if license.isFamilyMember { chip("FAMILY", system: "person.2.fill", filled: false) }
                if !license.isRoyale && !license.isFamilyMember {
                    chip("STANDARD", system: "person.fill", filled: false)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statesProgress: some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack {
                Text("STATES & PROVINCES")
                    .font(.system(size: 7 * s, weight: .bold)).kerning(0.6 * s).foregroundStyle(.secondary)
                Spacer()
                Text("\(license.statesProvincesFound)/\(license.totalStatesProvinces)")
                    .font(.system(size: 10 * s, weight: .heavy, design: .rounded)).foregroundStyle(accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * license.completion)
                }
            }
            .frame(height: 6 * s)
        }
    }

    private var frontFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ISSUED \(issueDateString)")
                    .font(.system(size: 7.5 * s, weight: .semibold, design: .monospaced))
                Text("NO. \(license.resolvedLicenseNumber)")
                    .font(.system(size: 7.5 * s, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 3 * s) {
                Image(systemName: "arrow.triangle.2.circlepath"); Text("STATS")
            }
            .font(.system(size: 7.5 * s, weight: .bold)).foregroundStyle(accent)
        }
    }

    // MARK: Back

    private var backSide: some View {
        VStack(alignment: .leading, spacing: 9 * s) {
            HStack {
                Text("TRAVEL RECORD")
                    .font(.system(size: 11 * s, weight: .heavy, design: .rounded)).kerning(1 * s)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4 * s) {
                    Image(systemName: "car.fill").font(.system(size: 9 * s, weight: .bold))
                    Text("RoadTrip Royale").font(.system(size: 9 * s, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(accent)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1 * s)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10 * s),
                                GridItem(.flexible(), spacing: 10 * s)], spacing: 7 * s) {
                statCell("road.lanes", "TRIPS TAKEN", license.tripsTaken.formatted())
                statCell("gamecontroller.fill", "GAMES PLAYED", license.gamesPlayed.formatted())
                statCell("trophy.fill", "GAMES WON", "\(license.gamesWon)  ·  \(license.winRateText)")
                statCell("rectangle.on.rectangle", "PLATES FOUND", license.platesFound.formatted())
                statCell("map.fill", "STATES / PROV.", "\(license.statesProvincesFound)/\(license.totalStatesProvinces)")
                statCell("bolt.fill", "XP", license.xp.formatted())
            }

            if !license.badges.isEmpty {
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("BADGES").font(.system(size: 7 * s, weight: .bold)).kerning(0.8 * s)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6 * s) {
                        ForEach(license.badges.prefix(7)) { badge in
                            Image(systemName: badge.symbol)
                                .font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 23 * s, height: 23 * s)
                                .background(LinearGradient(colors: [badge.color, badge.color.opacity(0.7)],
                                                           startPoint: .top, endPoint: .bottom), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.8 * s))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                barcode
                Spacer()
                HStack(spacing: 3 * s) {
                    Image(systemName: "arrow.triangle.2.circlepath"); Text("FLIP")
                }
                .font(.system(size: 7.5 * s, weight: .bold)).foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 15 * s)
        .padding(.vertical, 12 * s)
    }

    private func statCell(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7 * s) {
            Image(systemName: symbol).font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(accent).frame(width: 15 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 12.5 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.5)
                Text(label).font(.system(size: 6.5 * s, weight: .semibold)).kerning(0.4 * s)
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Reusable bits

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1 * s) {
            Text(label).font(.system(size: 7 * s, weight: .bold)).kerning(0.8 * s).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14 * s, weight: .bold)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 14 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.system(size: 7 * s, weight: .bold)).kerning(0.6 * s).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String, system: String, filled: Bool) -> some View {
        HStack(spacing: 3 * s) {
            Image(systemName: system).font(.system(size: 8 * s, weight: .bold))
            Text(text).font(.system(size: 8 * s, weight: .heavy, design: .rounded)).kerning(0.4 * s)
        }
        .padding(.horizontal, 7 * s).padding(.vertical, 3.5 * s)
        .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(accent))
        .background(filled ? AnyShapeStyle(accent) : AnyShapeStyle(accent.opacity(0.14)), in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(filled ? 0 : 0.4), lineWidth: 1 * s))
    }

    private var barcode: some View {
        HStack(spacing: 1.1 * s) {
            ForEach(barWidths.indices, id: \.self) { i in
                Rectangle().fill(Color.primary.opacity(0.85)).frame(width: barWidths[i] * s)
            }
        }
        .frame(height: 22 * s)
    }

    private var barWidths: [CGFloat] {
        let digits = license.resolvedLicenseNumber.compactMap { $0.wholeNumberValue }
        let source = digits.isEmpty ? [1, 2, 3, 1, 2] : digits
        return (0..<24).map { i in 1 + CGFloat(source[i % source.count] % 3) }
    }

    // MARK: Cosmetic layers

    private var headerGradient: LinearGradient {
        let colors: [Color]
        if let p = style.palette {
            colors = p.headerColors
        } else if case .foil(let metal) = style.finish {
            colors = [metal, metal.opacity(0.72)]
        } else {
            colors = [accent, accent.opacity(0.78)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Carbon weave — drawn under content.
    @ViewBuilder private var materialOverlay: some View {
        if case .carbon = style.finish {
            ZStack {
                Color.black.opacity(scheme == .dark ? 0.22 : 0.10)
                Canvas { ctx, size in
                    let spacing: CGFloat = 7 * s
                    var p1 = Path(); var x = -size.height
                    while x < size.width { p1.move(to: CGPoint(x: x, y: 0))
                        p1.addLine(to: CGPoint(x: x + size.height, y: size.height)); x += spacing }
                    ctx.stroke(p1, with: .color(.white.opacity(0.06)), lineWidth: 1)
                    var p2 = Path(); x = 0
                    while x < size.width + size.height { p2.move(to: CGPoint(x: x, y: 0))
                        p2.addLine(to: CGPoint(x: x - size.height, y: size.height)); x += spacing }
                    ctx.stroke(p2, with: .color(.black.opacity(0.10)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Holographic / foil sheen — drawn over content at low opacity.
    @ViewBuilder private var sheenOverlay: some View {
        switch style.finish {
        case .holographic:
            LinearGradient(colors: [.clear,
                                    Color.pink.opacity(0.20), Color.purple.opacity(0.14),
                                    Color.cyan.opacity(0.20), Color.green.opacity(0.14), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        case .foil:
            LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }

    /// A slow shine band sweeping across premium cards.
    private var animatedShine: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.30), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.4)
                .rotationEffect(.degrees(20))
                .offset(x: -w * 0.7 + shinePhase * (w * 1.8))
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var trimOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        switch style.trim {
        case .standard:
            shape.strokeBorder(license.isRoyale ? accent.opacity(0.5) : hairline, lineWidth: 1 * s)
        case .glow:
            shape.strokeBorder(accent.opacity(0.85), lineWidth: 1.5 * s)
        case .double:
            ZStack {
                shape.strokeBorder(accent.opacity(0.85), lineWidth: 1.2 * s)
                RoundedRectangle(cornerRadius: corner - 3 * s, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1 * s)
                    .padding(3 * s)
            }
        case .dashed:
            shape.strokeBorder(accent.opacity(0.85),
                               style: StrokeStyle(lineWidth: 1.2 * s, dash: [5 * s, 3 * s]))
        }
    }

    private var glowColor: Color { style.trim == .glow ? accent.opacity(0.5) : .clear }

    private func stampView(_ stamp: LicenseStamp) -> some View {
        let c = stamp.color ?? accent
        return VStack(spacing: 1 * s) {
            Image(systemName: stamp.symbol).font(.system(size: 15 * s, weight: .black))
            Text(stamp.text).font(.system(size: 9 * s, weight: .black, design: .rounded)).kerning(1 * s)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10 * s).padding(.vertical, 7 * s)
        .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous).strokeBorder(c, lineWidth: 2 * s))
        .overlay(RoundedRectangle(cornerRadius: 11 * s, style: .continuous)
            .strokeBorder(c.opacity(0.5), lineWidth: 1 * s).padding(-3 * s))
        .rotationEffect(.degrees(-14))
        .opacity(0.6)
        .padding(.trailing, 14 * s)
        .padding(.bottom, 30 * s)
    }

    private var hairline: Color {
        scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: scheme == .dark ? [Color(white: 0.17), Color(white: 0.11)]
                                    : [Color(white: 1.00), Color(white: 0.93)],
            startPoint: .top, endPoint: .bottom)
    }

    private var watermark: some View {
        // resizable + scaledToFit in a fixed square frame normalizes every
                // emblem to the same box, so narrow glyphs (e.g. bolt.fill) sit in the
                // same spot as wide ones (e.g. map.fill) instead of drifting off-center.
                Image(systemName: style.emblem.symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * 0.85, height: height * 0.85)
                    .foregroundStyle(accent.opacity(scheme == .dark ? 0.10 : 0.06))
                    .rotationEffect(.degrees(-12))
                    .offset(x: width * 0.26, y: height * 0.16)
                    .allowsHitTesting(false)
        //Image(systemName: style.emblem.symbol)
        //    .font(.system(size: height * 0.95))
        //   .foregroundStyle(accent.opacity(scheme == .dark ? 0.10 : 0.06))
        //    .rotationEffect(.degrees(-12))
        //    .offset(x: width * 0.32, y: height * 0.22)
        //    .allowsHitTesting(false)
    }

    private var issueDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd/yyyy"
        return f.string(from: license.issueDate)
    }
}

// MARK: - Convenience initializers

extension UserDriversLicenseCard where Portrait == LicenseImagePortrait {
    init(license: UserDriversLicense, width: CGFloat = 360,
         style: LicenseStyle = .standard, characterImage: Image) {
        self.init(license: license, width: width, style: style) {
            LicenseImagePortrait(image: characterImage)
        }
    }
}

extension UserDriversLicenseCard where Portrait == LicensePortraitPlaceholder {
    init(license: UserDriversLicense, width: CGFloat = 360, style: LicenseStyle = .standard) {
        self.init(license: license, width: width, style: style) { LicensePortraitPlaceholder() }
    }
}

// MARK: - Previews

/// A consistent, drop-in control for the card's accessory slot. Reads on any
/// finish (translucent dark disc + hairline ring). Size it to taste.
struct LicenseCornerButton: View {
    let systemImage: String
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.4), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PreviewPortrait: View {
    var accent: Color = .blue
    var body: some View {
        // The symbol is sized as a fraction of the (scaling) frame via
                // GeometryReader, so it shrinks/grows with the card — demonstrating
                // the same proportional behavior a real `.resizable()` avatar gets.
                
        ZStack {
            LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
            // Image(systemName: "figure.wave").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            GeometryReader { geo in
                        Image(systemName: "figure.wave")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.75)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.white)
                    }
        }
    }
}

/// Accessory slot: an edit button that doesn't fight the flip gesture, plus a
/// Menu showing the slot accepts any control. Tap the card to flip — the
/// accessory hides on the back.
private struct AccessoryDemo: View {
    @State private var lastAction = "—"
    var body: some View {
        VStack(spacing: 16) {
            UserDriversLicenseCard(license: .sample, width: 340, style: .goldFoil) {
                PreviewPortrait(accent: .blue)
            }
            .accessory(alignment: .bottomTrailing) {
                Menu {
                    Button("Edit") { lastAction = "edit" }
                    Button("Share") { lastAction = "share" }
                    Button("Set Active") { lastAction = "set active" }
                } label: {
                    LicenseCornerButton(systemImage: "ellipsis") { }
                        .allowsHitTesting(false)   // let the Menu own the tap
                }
            }
            Text("last action: \(lastAction)")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview("Accessory") { AccessoryDemo() }


/// Confirms everything — including the avatar — scales proportionally.
#Preview("Sizes") {
    VStack(spacing: 24) {
        UserDriversLicenseCard(license: .sample, width: 340, style: .neonNights) { PreviewPortrait() }
        UserDriversLicenseCard(license: .sample, width: 240, style: .neonNights) { PreviewPortrait() }
        UserDriversLicenseCard(license: .sample, width: 170, style: .neonNights) { PreviewPortrait() }
    }
    .padding()
}

/// Full grantable catalog (`LicenseCosmetic.catalog`), shine disabled for canvas perf.
#Preview("Catalog — Light") {
    LicenseCatalogPreviewGallery()
        .preferredColorScheme(.light)
}

#Preview("Catalog — Dark") {
    LicenseCatalogPreviewGallery()
        .preferredColorScheme(.dark)
}

/// Default accent / header / outline when no palette — driven by completion class.
#Preview("Class Accents") {
    ScrollView {
        VStack(spacing: 22) {
            ForEach(["D", "C", "B", "A", "S"], id: \.self) { licenseClass in
                let license = UserDriversLicense.sampleForClass(licenseClass)
                label("Class \(licenseClass) · \(license.statesProvincesFound)/\(license.totalStatesProvinces)")
                UserDriversLicenseCard(license: license, width: 320, style: .standard) {
                    PreviewPortrait(accent: license.accent)
                }
            }
        }
        .padding()
    }
}

/// Front chips + Royale crown / standard trim vs hairline.
#Preview("Membership") {
    ScrollView {
        VStack(spacing: 22) {
            label("Royale + Family")
            UserDriversLicenseCard(
                license: .previewSample(isRoyale: true, isFamilyMember: true),
                width: 320,
                style: .standard
            ) { PreviewPortrait(accent: .orange) }

            label("Family only")
            UserDriversLicenseCard(
                license: .previewSample(isRoyale: false, isFamilyMember: true),
                width: 320,
                style: .standard
            ) { PreviewPortrait(accent: .teal) }

            label("Standard (neither)")
            UserDriversLicenseCard(
                license: .previewSample(isRoyale: false, isFamilyMember: false),
                width: 320,
                style: .standard
            ) { PreviewPortrait(accent: .gray) }
        }
        .padding()
    }
}

/// Stamp builders not represented as distinct catalog rows.
#Preview("Stamps / Builders") {
    ScrollView {
        VStack(spacing: 22) {
            label("Rank-up Lv 50")
            UserDriversLicenseCard(
                license: .sample,
                width: 320,
                style: .rankUp(level: 50, palette: .midnight)
            ) { PreviewPortrait(accent: .indigo) }

            label("Season pass · Route 66")
            UserDriversLicenseCard(
                license: .sample,
                width: 320,
                style: .seasonPass("Route 66", palette: .summerRoad)
            ) { PreviewPortrait(accent: .orange) }
        }
        .padding()
    }
}

private struct LicenseCatalogPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ForEach(LicenseCosmetic.catalog) { cosmetic in
                    label("\(cosmetic.name) · \(cosmetic.rarity.title)")
                    UserDriversLicenseCard(
                        license: .sample,
                        width: 320,
                        style: cosmetic.style.staticPreview
                    ) {
                        PreviewPortrait(accent: cosmetic.style.palette?.accent ?? .blue)
                    }
                }
            }
            .padding()
        }
    }
}

@ViewBuilder private func label(_ text: String) -> some View {
    Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}
