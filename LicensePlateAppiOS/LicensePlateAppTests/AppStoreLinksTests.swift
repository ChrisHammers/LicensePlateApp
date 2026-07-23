//
//  AppStoreLinksTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AppStoreLinksTests {

    @Test func writeReviewURLFromNumericAppleID() {
        let url = AppStoreLinks.writeReviewURL(appleAppID: "123456789", storeURLString: nil)
        #expect(url?.absoluteString == "https://apps.apple.com/app/id123456789?action=write-review")
    }

    @Test func writeReviewURLFromStoreURLWhenAppleIDMissing() {
        let url = AppStoreLinks.writeReviewURL(
            appleAppID: "",
            storeURLString: "https://apps.apple.com/us/app/roadtrip-royale/id987654321"
        )
        #expect(url?.absoluteString == "https://apps.apple.com/app/id987654321?action=write-review")
    }

    @Test func prefersInfoPlistAppleIDOverStoreURL() {
        let url = AppStoreLinks.writeReviewURL(
            appleAppID: "111",
            storeURLString: "https://apps.apple.com/app/id222"
        )
        #expect(url?.absoluteString == "https://apps.apple.com/app/id111?action=write-review")
    }

    @Test func returnsNilWhenNoAppleIDResolvable() {
        #expect(AppStoreLinks.writeReviewURL(appleAppID: "", storeURLString: nil) == nil)
        #expect(AppStoreLinks.writeReviewURL(appleAppID: "abc", storeURLString: "https://example.com") == nil)
    }

    @Test func productURLOmitsWriteReviewAction() {
        let url = AppStoreLinks.productURL(appleAppID: "555", storeURLString: nil)
        #expect(url?.absoluteString == "https://apps.apple.com/app/id555")
    }
}
