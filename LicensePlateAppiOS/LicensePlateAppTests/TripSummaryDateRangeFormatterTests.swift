//
//  TripSummaryDateRangeFormatterTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSummaryDateRangeFormatterTests {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var start: Date {
        Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
    }

    private var end: Date {
        Date(timeIntervalSince1970: 1_704_499_200) // 2024-01-06 00:00 UTC
    }

    @Test func startAndEndDateLinesAreSeparate() {
        let startLine = TripSummaryDateRangeFormatter.startDateLine(startedAt: start, formatter: formatter)
        let endLine = TripSummaryDateRangeFormatter.endDateLine(endedAt: end, formatter: formatter)
        #expect(startLine?.contains(formatter.string(from: start)) == true)
        #expect(endLine?.contains(formatter.string(from: end)) == true)
        #expect(startLine != endLine)
    }

    @Test func startDateLineNilWhenMissing() {
        #expect(TripSummaryDateRangeFormatter.startDateLine(startedAt: nil, formatter: formatter) == nil)
    }

    @Test func endDateLineNilWhenMissing() {
        #expect(TripSummaryDateRangeFormatter.endDateLine(endedAt: nil, formatter: formatter) == nil)
    }

    @Test func accessibilityLabelJoinsBothDates() {
        let label = TripSummaryDateRangeFormatter.accessibilityLabel(
            startedAt: start,
            endedAt: end,
            formatter: formatter
        )
        #expect(label?.contains(formatter.string(from: start)) == true)
        #expect(label?.contains(formatter.string(from: end)) == true)
    }

    @Test func compactDashRangeUsesSingleLine() {
        let text = TripSummaryDateRangeFormatter.compactDashRange(
            startedAt: start,
            endedAt: end,
            formatter: formatter
        )
        #expect(text.contains(" – "))
        #expect(text.contains(formatter.string(from: start)))
        #expect(text.contains(formatter.string(from: end)))
    }
}
