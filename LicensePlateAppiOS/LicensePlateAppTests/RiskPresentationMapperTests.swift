//
//  RiskPresentationMapperTests.swift
//  LicensePlateAppTests
//
//  Step 11 — RiskPresentationMapper: maps [RiskFlag] to presentation style.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct RiskPresentationMapperTests {

    private func makeFlag(severity: RiskSeverity, type: RiskFlagType = .duplicateDiscovery) -> RiskFlag {
        RiskFlag(type: type, severity: severity, source: .localHeuristic, presentationKey: "risk.test")
    }

    @Test func emptyFlagsReturnsNone() async throws {
        let style = RiskPresentationMapper().presentation(for: [])
        #expect(style == .none)
    }

    @Test func noticeSeverityReturnsToast() async throws {
        let flags = [makeFlag(severity: .notice)]
        let style = RiskPresentationMapper().presentation(for: flags)
        guard case .toast(let key) = style else { return #expect(Bool(false), "Expected toast") }
        #expect(key == "risk.toast.notice")
    }

    @Test func warningSeverityReturnsInlineHint() async throws {
        let flags = [makeFlag(severity: .warning)]
        let style = RiskPresentationMapper().presentation(for: flags)
        guard case .inlineHint(let key) = style else { return #expect(Bool(false), "Expected inlineHint") }
        #expect(key == "risk.inline.warning")
    }

    @Test func reviewSeverityReturnsReviewModal() async throws {
        let flags = [makeFlag(severity: .review)]
        let style = RiskPresentationMapper().presentation(for: flags)
        guard case .reviewModal(let titleKey, let bodyKey) = style else { return #expect(Bool(false), "Expected reviewModal") }
        #expect(titleKey == "risk.review.title")
        #expect(bodyKey == "risk.review.body")
    }

    @Test func highestSeverityWins() async throws {
        let flags = [
            makeFlag(severity: .notice),
            makeFlag(severity: .warning)
        ]
        let style = RiskPresentationMapper().presentation(for: flags)
        switch style {
        case .inlineHint: break
        default: #expect(Bool(false), "Expected inlineHint when highest is warning")
        }
    }
}
