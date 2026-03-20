//
//  LicensePlateScopeSettingsDraft.swift
//  LicensePlateApp
//
//  Editable license-plate scope (countries + territory flags) before persisting to GameInstance.
//

import Foundation
import Combine

@MainActor
final class LicensePlateScopeSettingsDraft: ObservableObject {
    @Published var includeUS: Bool
    @Published var includeCanada: Bool
    @Published var includeMexico: Bool
    @Published var includeUSTerritories: Bool
    @Published var includeDC: Bool
    @Published var includeCanadianTerritories: Bool

    init(
        includeUS: Bool,
        includeCanada: Bool,
        includeMexico: Bool,
        includeUSTerritories: Bool,
        includeDC: Bool,
        includeCanadianTerritories: Bool
    ) {
        self.includeUS = includeUS
        self.includeCanada = includeCanada
        self.includeMexico = includeMexico
        self.includeUSTerritories = includeUSTerritories
        self.includeDC = includeDC
        self.includeCanadianTerritories = includeCanadianTerritories
        applyParentGating()
    }

    /// UI convenience: territory toggles cannot apply without parent country.
    func applyParentGating() {
        if !includeUS {
            includeUSTerritories = false
            includeDC = false
        }
        if !includeCanada {
            includeCanadianTerritories = false
        }
    }
}
