//
//  PlateRegion.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation

struct PlateRegion: Identifiable, Hashable {
    enum Country: String, CaseIterable, Identifiable {
        case unitedStates = "United States"
        case canada = "Canada"
        case mexico = "Mexico"

        var id: String { rawValue }
    }

    let id: String
    let name: String
    let country: Country

    static let all: [PlateRegion] = {
        let usStates: [PlateRegion] = [
            .init(id: "us-al", name: "Alabama", country: .unitedStates),
            .init(id: "us-ak", name: "Alaska", country: .unitedStates),
            .init(id: "us-az", name: "Arizona", country: .unitedStates),
            .init(id: "us-ar", name: "Arkansas", country: .unitedStates),
            .init(id: "us-ca", name: "California", country: .unitedStates),
            .init(id: "us-co", name: "Colorado", country: .unitedStates),
            .init(id: "us-ct", name: "Connecticut", country: .unitedStates),
            .init(id: "us-de", name: "Delaware", country: .unitedStates),
            .init(id: "us-fl", name: "Florida", country: .unitedStates),
            .init(id: "us-ga", name: "Georgia", country: .unitedStates),
            .init(id: "us-hi", name: "Hawaii", country: .unitedStates),
            .init(id: "us-id", name: "Idaho", country: .unitedStates),
            .init(id: "us-il", name: "Illinois", country: .unitedStates),
            .init(id: "us-in", name: "Indiana", country: .unitedStates),
            .init(id: "us-ia", name: "Iowa", country: .unitedStates),
            .init(id: "us-ks", name: "Kansas", country: .unitedStates),
            .init(id: "us-ky", name: "Kentucky", country: .unitedStates),
            .init(id: "us-la", name: "Louisiana", country: .unitedStates),
            .init(id: "us-me", name: "Maine", country: .unitedStates),
            .init(id: "us-md", name: "Maryland", country: .unitedStates),
            .init(id: "us-ma", name: "Massachusetts", country: .unitedStates),
            .init(id: "us-mi", name: "Michigan", country: .unitedStates),
            .init(id: "us-mn", name: "Minnesota", country: .unitedStates),
            .init(id: "us-ms", name: "Mississippi", country: .unitedStates),
            .init(id: "us-mo", name: "Missouri", country: .unitedStates),
            .init(id: "us-mt", name: "Montana", country: .unitedStates),
            .init(id: "us-ne", name: "Nebraska", country: .unitedStates),
            .init(id: "us-nv", name: "Nevada", country: .unitedStates),
            .init(id: "us-nh", name: "New Hampshire", country: .unitedStates),
            .init(id: "us-nj", name: "New Jersey", country: .unitedStates),
            .init(id: "us-nm", name: "New Mexico", country: .unitedStates),
            .init(id: "us-ny", name: "New York", country: .unitedStates),
            .init(id: "us-nc", name: "North Carolina", country: .unitedStates),
            .init(id: "us-nd", name: "North Dakota", country: .unitedStates),
            .init(id: "us-oh", name: "Ohio", country: .unitedStates),
            .init(id: "us-ok", name: "Oklahoma", country: .unitedStates),
            .init(id: "us-or", name: "Oregon", country: .unitedStates),
            .init(id: "us-pa", name: "Pennsylvania", country: .unitedStates),
            .init(id: "us-ri", name: "Rhode Island", country: .unitedStates),
            .init(id: "us-sc", name: "South Carolina", country: .unitedStates),
            .init(id: "us-sd", name: "South Dakota", country: .unitedStates),
            .init(id: "us-tn", name: "Tennessee", country: .unitedStates),
            .init(id: "us-tx", name: "Texas", country: .unitedStates),
            .init(id: "us-ut", name: "Utah", country: .unitedStates),
            .init(id: "us-vt", name: "Vermont", country: .unitedStates),
            .init(id: "us-va", name: "Virginia", country: .unitedStates),
            .init(id: "us-wa", name: "Washington", country: .unitedStates),
            .init(id: "us-wv", name: "West Virginia", country: .unitedStates),
            .init(id: "us-wi", name: "Wisconsin", country: .unitedStates),
            .init(id: "us-wy", name: "Wyoming", country: .unitedStates),
            .init(id: "us-dc", name: "District of Columbia", country: .unitedStates),
            .init(id: "us-pr", name: "Puerto Rico", country: .unitedStates),
            .init(id: "us-gu", name: "Guam", country: .unitedStates),
            .init(id: "us-vi", name: "U.S. Virgin Islands", country: .unitedStates),
            .init(id: "us-as", name: "American Samoa", country: .unitedStates),
            .init(id: "us-mp", name: "Northern Mariana Islands", country: .unitedStates)
        ]

        let canadianProvinces: [PlateRegion] = [
            .init(id: "ca-ab", name: "Alberta", country: .canada),
            .init(id: "ca-bc", name: "British Columbia", country: .canada),
            .init(id: "ca-mb", name: "Manitoba", country: .canada),
            .init(id: "ca-nb", name: "New Brunswick", country: .canada),
            .init(id: "ca-nl", name: "Newfoundland and Labrador", country: .canada),
            .init(id: "ca-nt", name: "Northwest Territories", country: .canada),
            .init(id: "ca-ns", name: "Nova Scotia", country: .canada),
            .init(id: "ca-nu", name: "Nunavut", country: .canada),
            .init(id: "ca-on", name: "Ontario", country: .canada),
            .init(id: "ca-pe", name: "Prince Edward Island", country: .canada),
            .init(id: "ca-qc", name: "Quebec", country: .canada),
            .init(id: "ca-sk", name: "Saskatchewan", country: .canada),
            .init(id: "ca-yt", name: "Yukon", country: .canada)
        ]

        let mexicanStates: [PlateRegion] = [
            .init(id: "mx-ags", name: "Aguascalientes", country: .mexico),
            .init(id: "mx-bcn", name: "Baja California", country: .mexico),
            .init(id: "mx-bcs", name: "Baja California Sur", country: .mexico),
            .init(id: "mx-cam", name: "Campeche", country: .mexico),
            .init(id: "mx-chp", name: "Chiapas", country: .mexico),
            .init(id: "mx-chh", name: "Chihuahua", country: .mexico),
            .init(id: "mx-coa", name: "Coahuila", country: .mexico),
            .init(id: "mx-col", name: "Colima", country: .mexico),
            .init(id: "mx-dur", name: "Durango", country: .mexico),
            .init(id: "mx-gua", name: "Guanajuato", country: .mexico),
            .init(id: "mx-gro", name: "Guerrero", country: .mexico),
            .init(id: "mx-hid", name: "Hidalgo", country: .mexico),
            .init(id: "mx-jal", name: "Jalisco", country: .mexico),
            .init(id: "mx-mex", name: "State of Mexico", country: .mexico),
            .init(id: "mx-mic", name: "Michoacan", country: .mexico),
            .init(id: "mx-mor", name: "Morelos", country: .mexico),
            .init(id: "mx-nay", name: "Nayarit", country: .mexico),
            .init(id: "mx-nle", name: "Nuevo Leon", country: .mexico),
            .init(id: "mx-oax", name: "Oaxaca", country: .mexico),
            .init(id: "mx-pue", name: "Puebla", country: .mexico),
            .init(id: "mx-que", name: "Queretaro", country: .mexico),
            .init(id: "mx-roo", name: "Quintana Roo", country: .mexico),
            .init(id: "mx-slp", name: "San Luis Potosi", country: .mexico),
            .init(id: "mx-sin", name: "Sinaloa", country: .mexico),
            .init(id: "mx-son", name: "Sonora", country: .mexico),
            .init(id: "mx-tab", name: "Tabasco", country: .mexico),
            .init(id: "mx-tam", name: "Tamaulipas", country: .mexico),
            .init(id: "mx-tla", name: "Tlaxcala", country: .mexico),
            .init(id: "mx-ver", name: "Veracruz", country: .mexico),
            .init(id: "mx-yuc", name: "Yucatan", country: .mexico),
            .init(id: "mx-zac", name: "Zacatecas", country: .mexico),
            .init(id: "mx-cmx", name: "Mexico City", country: .mexico)
        ]

        return (usStates + canadianProvinces + mexicanStates)
            .sorted { lhs, rhs in
                if lhs.country == rhs.country {
                    lhs.name < rhs.name
                } else {
                    lhs.country.rawValue < rhs.country.rawValue
                }
            }
    }()

    static func groupedByCountry() -> [(country: Country, regions: [PlateRegion])] {
        let grouped = Dictionary(grouping: PlateRegion.all, by: \.country)
        return Country.allCases.map { country in
            let regions = (grouped[country] ?? []).sorted { $0.name < $1.name }
            return (country, regions)
        }
    }
}

