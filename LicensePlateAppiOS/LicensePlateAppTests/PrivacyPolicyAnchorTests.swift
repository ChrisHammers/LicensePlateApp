//
//  PrivacyPolicyAnchorTests.swift
//  LicensePlateAppTests
//
//  FR-103(c) (F-21 slice 2): every consent card links to its own Privacy Policy section 12
//  subsection. These pin that every scope anchor is a scroll id the rendered PrivacyView
//  actually registers, and that each subsection's title and body resolve to real text in
//  the en, es and fr bundles (each loaded explicitly, see `ConsentTextBundles`).
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct PrivacyPolicyAnchorTests {

    @Test func everyScopeAnchorIsRegisteredInTheSectionList() {
        #expect(PrivacyView.sectionAnchors == ConsentScopePolicyAnchor.allCases)
        // And every scope's own anchor is among them.
        for scope in ConsentScopeId.allCases {
            #expect(PrivacyView.sectionAnchors.contains(scope.policyAnchor), "\(scope.rawValue)")
        }
    }

    /// The subsections are scroll targets by anchor; the other sections keep their titles
    /// as ids, so the existing "12. Children" deep link still lands.
    @Test func subsectionIdsAreTheAnchorsAndTheChildrenTitleStaysAnId() {
        let ids = PrivacyView.sections.map(\.id)
        for anchor in ConsentScopePolicyAnchor.allCases {
            #expect(ids.filter { $0 == anchor.rawValue }.count == 1, "\(anchor.rawValue)")
        }
        #expect(ids.contains(PrivacyView.childrenSectionTitle))
        #expect(Set(ids).count == ids.count)
    }

    /// 12.1–12.5 follow the section 12 title directly, in catalog order.
    @Test func subsectionsFollowTheChildrenSectionInCatalogOrder() throws {
        let sections = PrivacyView.sections
        let childrenIndex = try #require(
            sections.firstIndex { $0.title == PrivacyView.childrenSectionTitle }
        )
        let following = sections[(childrenIndex + 1)...].prefix(ConsentScopePolicyAnchor.allCases.count)
        #expect(following.map(\.anchor) == ConsentScopePolicyAnchor.allCases.map(Optional.some))
    }

    @Test func everySubsectionResolvesInEveryLanguage() throws {
        for subsection in PrivacyView.childrenSubsections {
            for language in ConsentTextBundles.languages {
                for key in [subsection.titleKey, subsection.bodyKey] {
                    let value = try ConsentTextBundles.value(for: key, language: language)
                    #expect(!value.isEmpty, "\(language) \(key)")
                    #expect(value != key, "\(language) \(key)")
                }
            }
        }
    }

    @Test func introAndHeaderDateResolveInEveryLanguage() throws {
        for language in ConsentTextBundles.languages {
            for key in [PrivacyView.childrenIntroBodyKey, PrivacyView.lastUpdatedKey] {
                let value = try ConsentTextBundles.value(for: key, language: language)
                #expect(!value.isEmpty, "\(language) \(key)")
                #expect(value != key, "\(language) \(key)")
            }
        }
        #expect(try ConsentTextBundles.value(for: PrivacyView.lastUpdatedKey, language: "en")
            == "Last updated: November 17, 2026")
    }

    /// Terms keeps its own date: only the Privacy Policy changed.
    @Test func termsDateIsUnchanged() throws {
        #expect(try ConsentTextBundles.value(for: "Last updated: August 8, 2026", language: "en")
            == "Last updated: August 8, 2026")
    }
}
