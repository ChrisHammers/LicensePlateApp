//
//  FirebaseBuildConfigurationTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct FirebaseBuildConfigurationTests {

    @Test func productionProjectIDMatchesReleaseExpectation() {
        #expect(FirebaseBuildConfiguration.productionProjectID == "roadtrip-royale-b694d")
    }

    @Test func isProductionProjectIDAcceptsCurrentProduction() {
        #expect(FirebaseBuildConfiguration.isProductionProjectID("roadtrip-royale-b694d"))
    }

    @Test func isProductionProjectIDRejectsDevelopment() {
        #expect(!FirebaseBuildConfiguration.isProductionProjectID("roadtrip-royale-dev-d2652"))
    }

    @Test func isProductionProjectIDRejectsLegacyBareProductionId() {
        #expect(!FirebaseBuildConfiguration.isProductionProjectID("roadtrip-royale"))
    }

    @Test func isDevelopmentProjectIDAcceptsDev() {
        #expect(FirebaseBuildConfiguration.isDevelopmentProjectID("roadtrip-royale-dev-d2652"))
    }

    @Test func isDevelopmentProjectIDRejectsProduction() {
        #expect(!FirebaseBuildConfiguration.isDevelopmentProjectID("roadtrip-royale-b694d"))
    }

    @Test func projectIDFromPlistReadsPROJECT_IDKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FirebaseBuildConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let plistURL = directory.appendingPathComponent("test.plist")
        let plist: [String: Any] = ["PROJECT_ID": FirebaseBuildConfiguration.productionProjectID]
        try (plist as NSDictionary).write(to: plistURL)

        #expect(FirebaseBuildConfiguration.projectID(fromPlistAt: plistURL.path) == "roadtrip-royale-b694d")
    }
}
