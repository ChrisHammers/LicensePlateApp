//
//  CountryScopeSection.swift
//  LicensePlateApp
//
//  Shared country and territory toggles for trip and game setup.
//

import SwiftUI

struct CountryScopeSection: View {
    @Binding var includeUS: Bool
    @Binding var includeCanada: Bool
    @Binding var includeMexico: Bool
    @Binding var includeUSTerritories: Bool
    @Binding var includeDC: Bool
    @Binding var includeCanadianTerritories: Bool
    var validationMessage: String?
    var onCountryToggleChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Countries to Include".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)

            SettingToggleRow(title: "United States".localized, isOn: $includeUS)
                .onChange(of: includeUS) { _, _ in onCountryToggleChanged() }
            SettingToggleRow(title: "Canada".localized, isOn: $includeCanada)
                .onChange(of: includeCanada) { _, _ in onCountryToggleChanged() }
            SettingToggleRow(title: "Mexico".localized, isOn: $includeMexico)

            Text("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)

            SettingToggleRow(
                title: "Include US Territories".localized,
                description: "Puerto Rico, Guam, US Virgin Islands, American Samoa, Northern Mariana Islands".localized,
                isOn: $includeUSTerritories
            )
            .disabled(!includeUS)
            .opacity(includeUS ? 1.0 : 0.5)
            .accessibilityHint(includeUS ? "" : "Enable United States first".localized)

            SettingToggleRow(
                title: "Include Washington, DC".localized,
                description: "District of Columbia as its own plate region".localized,
                isOn: $includeDC
            )
            .disabled(!includeUS)
            .opacity(includeUS ? 1.0 : 0.5)
            .accessibilityHint(includeUS ? "" : "Enable United States first".localized)

            SettingToggleRow(
                title: "Include Canadian Territories".localized,
                description: "Nunavut, Northwest Territories, Yukon".localized,
                isOn: $includeCanadianTerritories
            )
            .disabled(!includeCanada)
            .opacity(includeCanada ? 1.0 : 0.5)
            .accessibilityHint(includeCanada ? "" : "Enable Canada first".localized)

            if let message = validationMessage {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.red)
                    .accessibilityLabel(message)
            }
        }
    }
}
