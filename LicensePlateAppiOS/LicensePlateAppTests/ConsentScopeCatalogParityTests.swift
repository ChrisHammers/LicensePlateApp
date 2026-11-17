//
//  ConsentScopeCatalogParityTests.swift
//  LicensePlateAppTests
//
//  FR-65 / FR-103: the consent scope catalog is pinned in BOTH runtimes — lattice
//  discipline. This suite pins the Swift `ConsentScopeId` / `ConsentScopeCatalog`
//  against the canonical fixture; the functions suite (`consentScopeParity.test.ts`)
//  byte-compares the two trees' copies and pins the TS constants against the same bytes.
//  Drift anywhere fails a suite.
//
//  The fixture is test-only and is read from the source tree via #filePath (the
//  AchievementEvaluatorParityTests precedent): no runtime code loads it, so a missing
//  file fails parity here rather than passing silently.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ConsentScopeCatalogParityTests {

    private struct Catalog: Decodable {
        let schema: Int
        let consentTextVersion: String
        let scopes: [Scope]
    }

    private struct Scope: Decodable {
        let id: String
        let availability: String
        let practiceVersion: Int
        let policyAnchor: String
    }

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("ConsentScopeCatalog.v1.json")

    private func loadCanonicalCatalog() throws -> Catalog {
        let data = try Data(contentsOf: Self.fixtureURL)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func fixtureDecodesAsSchemaOne() throws {
        let catalog = try loadCanonicalCatalog()
        #expect(catalog.schema == 1)
        #expect(catalog.scopes.count == ConsentScopeId.allCases.count)
    }

    @Test func idsAndOrderMatchTheCanonicalCatalog() throws {
        let catalog = try loadCanonicalCatalog()
        #expect(ConsentScopeId.allCases.map(\.rawValue) == catalog.scopes.map(\.id))
    }

    @Test func availabilityMatchesTheCanonicalCatalog() throws {
        let catalog = try loadCanonicalCatalog()
        #expect(
            ConsentScopeId.allCases.map(\.availability.rawValue) == catalog.scopes.map(\.availability)
        )
    }

    @Test func policyAnchorsMatchTheCanonicalCatalog() throws {
        let catalog = try loadCanonicalCatalog()
        #expect(
            ConsentScopeId.allCases.map(\.policyAnchor.rawValue) == catalog.scopes.map(\.policyAnchor)
        )
        // Every anchor belongs to exactly one scope.
        #expect(ConsentScopePolicyAnchor.allCases.map(\.rawValue).sorted()
            == catalog.scopes.map(\.policyAnchor).sorted())
    }

    @Test func consentTextVersionMatchesTheCanonicalCatalog() throws {
        let catalog = try loadCanonicalCatalog()
        #expect(ConsentScopeCatalog.consentTextVersion == catalog.consentTextVersion)
    }

    @Test func launchSelectionIsExactlyTheRequiredScopes() {
        #expect(ConsentScopeCatalog.launchSelection == [.core])
        #expect(
            ConsentScopeCatalog.launchSelection
                == ConsentScopeId.allCases.filter { $0.availability == .required }
        )
    }
}
