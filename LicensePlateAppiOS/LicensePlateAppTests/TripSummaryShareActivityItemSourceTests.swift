//
//  TripSummaryShareActivityItemSourceTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
import UIKit
@testable import LicensePlateApp

struct TripSummaryShareActivityItemSourceTests {

    @Test func sanitizedFileNameUsesTripTitleAndJpgExtension() {
        let name = TripSummaryShareActivityItemSource.sanitizedFileName(from: "Coastal Escape")
        #expect(name == "RoadTripRoyale-Coastal Escape.jpg")
    }

    @Test func sanitizedFileNameStripsIllegalCharacters() {
        let name = TripSummaryShareActivityItemSource.sanitizedFileName(from: "Trip/Name: One?")
        #expect(name == "RoadTripRoyale-Trip-Name- One.jpg")
    }

    @Test func activityItemSourceWritesNamedJpeg() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let source = try #require(TripSummaryShareActivityItemSource(image: image, tripName: "Canyon Run"))
        #expect(source.fileURL.lastPathComponent == "RoadTripRoyale-Canyon Run.jpg")
        #expect(FileManager.default.fileExists(atPath: source.fileURL.path))
        defer { try? FileManager.default.removeItem(at: source.fileURL) }
    }
}
