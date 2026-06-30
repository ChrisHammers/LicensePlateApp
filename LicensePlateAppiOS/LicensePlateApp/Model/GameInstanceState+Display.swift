//
//  GameInstanceState+Display.swift
//  LicensePlateApp
//
//  Localized lifecycle labels shared by trip dashboard and game settings.
//

import Foundation

extension GameInstanceState {

    var localizedDisplayName: String {
        switch self {
        case .created: return "Not started".localized
        case .started: return "In progress".localized
        case .ended: return "Ended".localized
        case .completed: return "Completed".localized
        }
    }

    var showsInProgressIndicator: Bool {
        self == .started
    }
}
