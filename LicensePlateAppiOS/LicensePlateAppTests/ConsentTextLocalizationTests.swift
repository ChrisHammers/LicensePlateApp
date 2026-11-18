//
//  ConsentTextLocalizationTests.swift
//  LicensePlateAppTests
//
//  F-21 slice 2 (FR-65 / FR-103): the consent text the app shows is the owner-approved
//  copy deck, word for word, and exists in every shipped language.
//
//  `ConsentCopyDeck.app.json` is a test-only copy of the deck's app-shown entries (the
//  notice.* keys are server text and are left out). It is read from the source tree via
//  #filePath, the ConsentScopeCatalogParityTests precedent. The strings are read from the
//  BUILT app's en / es / fr .lproj bundles, each loaded explicitly, so the simulator's
//  language never decides what is checked.
//

import Foundation
import Testing
@testable import LicensePlateApp

/// The app's per-language string bundles, loaded explicitly.
enum ConsentTextBundles {
    static let languages = ["en", "es", "fr"]

    /// Returned for a missing key; no real string contains a NUL.
    private static let missing = "\u{0}missing"

    struct MissingKey: Error, CustomStringConvertible {
        let key: String
        let language: String
        var description: String { "\(language): no value for \(key)" }
    }

    struct MissingBundle: Error, CustomStringConvertible {
        let language: String
        var description: String { "no \(language).lproj in the app bundle" }
    }

    static func bundle(_ language: String) throws -> Bundle {
        let app = Bundle(for: RemoteConfigService.self)
        guard let path = app.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            throw MissingBundle(language: language)
        }
        return bundle
    }

    /// The value for `key` in that language's Localizable.strings; throws when it is absent.
    static func value(for key: String, language: String) throws -> String {
        let value = try bundle(language).localizedString(forKey: key, value: missing, table: nil)
        guard value != missing else { throw MissingKey(key: key, language: language) }
        return value
    }

    static func has(_ key: String, language: String) throws -> Bool {
        try bundle(language).localizedString(forKey: key, value: missing, table: nil) != missing
    }
}

struct ConsentTextLocalizationTests {

    private struct Deck: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let key: String
        let english: String
    }

    private static let deckURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("ConsentCopyDeck.app.json")

    private func loadDeck() throws -> [Entry] {
        try JSONDecoder().decode(Deck.self, from: Data(contentsOf: Self.deckURL)).entries
    }

    @Test func deckFixtureHoldsOnlyAppShownKeys() throws {
        let entries = try loadDeck()
        #expect(entries.count == 57)
        #expect(Set(entries.map(\.key)).count == entries.count)
        #expect(!entries.contains { $0.key.hasPrefix("notice.") })
    }

    /// The approved English, character for character.
    @Test func englishEqualsTheApprovedDeck() throws {
        for entry in try loadDeck() {
            let value = try ConsentTextBundles.value(for: entry.key, language: "en")
            #expect(value == entry.english, "\(entry.key)")
        }
    }

    /// Every deck key exists, non-empty and resolved, in Spanish and French too.
    @Test func everyDeckKeyExistsInEveryLanguage() throws {
        for entry in try loadDeck() {
            for language in ConsentTextBundles.languages {
                let value = try ConsentTextBundles.value(for: entry.key, language: language)
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language) \(entry.key)")
                #expect(value != entry.key, "\(language) \(entry.key)")
            }
        }
    }

    /// The translations are translations: the long consent lines never ship as English.
    @Test func spanishAndFrenchAreNotEnglish() throws {
        for entry in try loadDeck() where entry.english.count > 40 {
            for language in ["es", "fr"] {
                let value = try ConsentTextBundles.value(for: entry.key, language: language)
                #expect(value != entry.english, "\(language) \(entry.key)")
            }
        }
    }

    /// Every key the card model can name is a deck key, so no card ever shows a raw key.
    @Test func everyCardKeyIsADeckKey() throws {
        let deckKeys = Set(try loadDeck().map(\.key))
        let liveScopes = Dictionary(
            uniqueKeysWithValues: ConsentScopeId.allCases.map {
                ($0.rawValue, $0 == .core ? ConsentScopeGrantState.granted : .unavailable)
            }
        )
        let modes: [ConsentScopeCardPolicy.Mode] = [
            .approval(kind: .join),
            .approval(kind: .memberFlag),
            .manage(status: .live, currentScopes: liveScopes)
        ]
        var keys: Set<String> = [
            ConsentScopeCardPolicy.sectionTitleKey,
            ConsentScopeCardPolicy.sectionIntroKey,
            ConsentScopeCardPolicy.fullPolicyLinksKey,
            ConsentScopeCardPolicy.policyLinkKey,
            ConsentScopeCardPolicy.accessibilityPolicyActionKey,
            ConsentScopeCardPolicy.manageTitleKey,
            ConsentScopeCardPolicy.manageUnavailableKey
        ]
        for status in [ConsentScopeStatus.live, .pending, .ended, .noRecord] {
            keys.insert(ConsentScopeCardPolicy.statusLineKey(for: status))
        }
        for mode in modes {
            for card in ConsentScopeCardPolicy.cards(mode: mode) {
                keys.formUnion([
                    card.nameKey, card.meaningKey, card.collectedKey, card.whoSeesKey,
                    card.stateKey, card.accessibilityValueKey
                ])
                keys.formUnion(
                    [card.notificationsKey, card.requiredReasonKey, card.frozenReasonKey, card.accessibilityHintKey]
                        .compactMap { $0 }
                )
            }
        }
        #expect(keys.subtracting(deckKeys).isEmpty, "\(keys.subtracting(deckKeys).sorted())")
    }

    /// Pre-release rule: the old summary is deleted, not left behind, in every language.
    @Test func thePolicySummaryIsGoneEverywhere() throws {
        for language in ConsentTextBundles.languages {
            #expect(try !ConsentTextBundles.has("family.child.policy_summary", language: language), "\(language)")
        }
    }
}
