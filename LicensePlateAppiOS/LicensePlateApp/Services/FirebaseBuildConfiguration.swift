//
//  FirebaseBuildConfiguration.swift
//  LicensePlateApp
//
//  Debug vs Release Firebase plist names and project IDs.
//  Release validation is enforced at build time (see Validate Firebase Release Config run script).
//

import Foundation

enum FirebaseBuildConfiguration {
    static let productionProjectID = "roadtrip-royale-b694d"
    static let developmentProjectID = "roadtrip-royale-dev-d2652"

    /// Stale production id that must not ship in Release (Firebase assigned suffix project).
    static let legacyProductionProjectID = "roadtrip-royale"

    static let debugPlistBaseName = "GoogleService-Info-Debug"
    static let releasePlistBaseName = "GoogleService-Info-Release"
    static let genericPlistBaseName = "GoogleService-Info"

    static var expectedPlistBaseName: String {
        #if DEBUG
        debugPlistBaseName
        #else
        releasePlistBaseName
        #endif
    }

    static func isProductionProjectID(_ projectID: String) -> Bool {
        projectID == productionProjectID
    }

    static func isDevelopmentProjectID(_ projectID: String) -> Bool {
        projectID == developmentProjectID
    }

    /// Reads `PROJECT_ID` from a plist on disk (parity with the Release build script).
    static func projectID(fromPlistAt path: String) -> String? {
        guard let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }
        return dictionary["PROJECT_ID"] as? String
    }
}
