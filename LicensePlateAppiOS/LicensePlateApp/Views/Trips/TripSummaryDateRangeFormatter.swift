//
//  TripSummaryDateRangeFormatter.swift
//  LicensePlateApp
//
//  Shared started–ended date copy for Trip Summary header and branded share card.
//

import Foundation

enum TripSummaryDateRangeFormatter {
    /// Separate start-date line. Nil when `startedAt` is missing.
    static func startDateLine(startedAt: Date?, formatter: DateFormatter) -> String? {
        guard let startedAt else { return nil }
        return "trip_summary.start_date %@".localized(formatter.string(from: startedAt))
    }

    /// Separate end-date line. Nil when `endedAt` is missing.
    static func endDateLine(endedAt: Date?, formatter: DateFormatter) -> String? {
        guard let endedAt else { return nil }
        return "trip_summary.end_date %@".localized(formatter.string(from: endedAt))
    }

    /// Combined VoiceOver label for both dates.
    static func accessibilityLabel(startedAt: Date?, endedAt: Date?, formatter: DateFormatter) -> String? {
        var parts: [String] = []
        if let start = startDateLine(startedAt: startedAt, formatter: formatter) {
            parts.append(start)
        }
        if let end = endDateLine(endedAt: endedAt, formatter: formatter) {
            parts.append(end)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Compact single-line range for list rows (e.g. "Jan 1, 2024 – Jan 6, 2024").
    static func compactDashRange(startedAt: Date?, endedAt: Date?, formatter: DateFormatter) -> String {
        switch (startedAt, endedAt) {
        case let (start?, end?):
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        case (let start?, nil):
            return formatter.string(from: start)
        case (nil, let end?):
            return formatter.string(from: end)
        case (nil, nil):
            return ""
        }
    }

    static func mediumDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    /// Date-only formatter for denser share-card layout.
    static func shareCardDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
