//
//  RiskPresentationMapper.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Maps risk flags to presentation style (toast, inline, modal); UI uses keys for copy.
//

import Foundation

enum RiskPresentationStyle: Sendable, Equatable {
    case none
    case toast(messageKey: String)
    case inlineHint(messageKey: String)
    case reviewModal(titleKey: String, bodyKey: String)
}

protocol RiskPresentationMapping: Sendable {
    func presentation(for flags: [RiskFlag]) -> RiskPresentationStyle
}

struct RiskPresentationMapper: RiskPresentationMapping {
    func presentation(for flags: [RiskFlag]) -> RiskPresentationStyle {
        guard let highest = flags.map(\.severity).max() else {
            return .none
        }
        switch highest {
        case .notice:
            return .toast(messageKey: "risk.toast.notice")
        case .warning:
            return .inlineHint(messageKey: "risk.inline.warning")
        case .review:
            return .reviewModal(titleKey: "risk.review.title", bodyKey: "risk.review.body")
        }
    }
}
