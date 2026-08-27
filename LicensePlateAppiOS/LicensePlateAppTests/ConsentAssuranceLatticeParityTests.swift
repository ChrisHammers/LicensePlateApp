//
//  ConsentAssuranceLatticeParityTests.swift
//  LicensePlateAppTests
//
//  FR-108(a): the consent assurance lattice is pinned by a closed enum in BOTH
//  runtimes — progression-catalog discipline. This suite pins the Swift
//  `ConsentAssurancePolicy` against the canonical bundled fixture; the functions
//  suite (`consentAssuranceParity.test.ts`) byte-compares the two trees' copies and
//  pins the TS lattice against the same bytes. Drift anywhere fails a suite.
//
//  The fixture is test-only: no runtime code loads it, so there is deliberately no
//  fallback — a missing resource fails parity here rather than passing silently.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ConsentAssuranceLatticeParityTests {

    private struct Lattice: Decodable {
        let version: Int
        let requiredLevel: Int
        let methods: [String: Int]
    }

    private func loadCanonicalLattice() throws -> Lattice {
        let bundle = Bundle(for: RemoteConfigService.self)
        let url = try #require(
            bundle.url(forResource: "ConsentAssuranceLattice.v1", withExtension: "json"),
            "ConsentAssuranceLattice.v1.json must be bundled with the app"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Lattice.self, from: data)
    }

    @Test func requiredLevelMatchesTheCanonicalLattice() throws {
        let lattice = try loadCanonicalLattice()
        #expect(ConsentAssurancePolicy.requiredLevel == lattice.requiredLevel)
    }

    @Test func methodLatticeMatchesExactlyAndIsClosedBothWays() throws {
        let lattice = try loadCanonicalLattice()
        let swiftLevels = Dictionary(
            uniqueKeysWithValues: ConsentAssurancePolicy.Method.allCases.map {
                ($0.rawValue, $0.assuranceLevel)
            }
        )
        // Dictionary equality is the two-way closure check: a method added on either
        // side, removed on either side, or re-leveled anywhere breaks it.
        #expect(swiftLevels == lattice.methods)
    }
}
