//
//  Color+Theme.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//


import SwiftUI

extension Color {
    enum Theme {
        // Background: Light cream -> Dark gray
        static let background = Color(
            light: Color(red: 0.95, green: 0.94, blue: 0.90),
            dark: Color(red: 0.11, green: 0.11, blue: 0.12)
        )
        
        // Primary Blue: Slightly brighter in dark mode for better contrast
        static let primaryBlue = Color(
            light: Color(red: 0.18, green: 0.44, blue: 0.64),
            dark: Color(red: 0.35, green: 0.60, blue: 0.80)
        )
        
        // Accent Yellow: Darkened in light mode for WCAG AA compliance (3:1 for UI components)
        // Light mode: Darkened from RGB(245,191,66) to RGB(200,150,0) for better contrast on cardBackground
        // Dark mode: Bright yellow for visibility on dark backgrounds
        static let accentYellow = Color(
            light: Color(red: 0.78, green: 0.59, blue: 0.0), // RGB(200, 150, 0) - WCAG AA compliant (3:1+)
            dark: Color(red: 1.0, green: 0.80, blue: 0.35)
        )
        
        // Soft Brown: Darkened in light mode for WCAG AA compliance (4.5:1 contrast)
        // Light mode: Darkened from RGB(148,115,89) to RGB(100,75,55) for better contrast
        // Dark mode: Lighter beige for readability on dark backgrounds
        static let softBrown = Color(
            light: Color(red: 0.39, green: 0.29, blue: 0.22), // RGB(100, 75, 55) - WCAG AA compliant
            dark: Color(red: 0.75, green: 0.65, blue: 0.55)
        )
        
        // Card Background: Light gray -> Dark gray
        static let cardBackground = Color(
            light: Color(red: 0.87, green: 0.85, blue: 0.80),
            dark: Color(red: 0.18, green: 0.18, blue: 0.20)
        )
        
        // Permission Yellow: For "While App is Open" status
        // Light mode: Darkened for WCAG AA compliance (3:1 for UI components)
        // Dark mode: Bright yellow for visibility on dark background
        static let permissionYellow = Color(
            light: Color(red: 0.80, green: 0.65, blue: 0.0), // RGB(204, 166, 0) - WCAG AA compliant //254,255,136, // original // light: Color(red: 0.85, green: 0.65, blue: 0.0), // not bad //light: Color(red: 0.85, green: 0.75, blue: 0.18),
            dark: Color(red: 1.0, green: 0.84, blue: 0.0)
        )
        
        // Permission Orange: For "Not Set" status
        // Light mode: Darkened for WCAG AA compliance (3:1 for UI components)
        // Dark mode: Orange-red for visibility on dark background
        static let permissionOrange = Color(
            light: Color(red: 0.75, green: 0.35, blue: 0.10), // RGB(191, 89, 26) - WCAG AA compliant
            dark: Color(red: 1.0, green: 0.37, blue: 0.12)
        )
        
        // Permission Orange Dark: For location "Not Set" (slightly more red)
        // Light mode: Darkened for WCAG AA compliance (3:1 for UI components)
        // Dark mode: Red-orange for visibility on dark background
        static let permissionOrangeDark = Color(
            light: Color(red: 0.75, green: 0.20, blue: 0.20), // RGB(191, 51, 51) - WCAG AA compliant
            dark: Color(red: 1.0, green: 0.14, blue: 0.14)
        )
    }
}

// Helper extension for creating adaptive colors
extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}


extension Color {
  init(red: Int, green: Int, blue: Int) {
    assert(red >= 0 && red <= 255, "Invalid red component")
    assert(green >= 0 && green <= 255, "Invalid green component")
    assert(blue >= 0 && blue <= 255, "Invalid blue component")

    //       self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1.0)
    self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0)
  }

  init(hex: Int) {
    self.init(
      red: (hex >> 16) & 0xFF,
      green: (hex >> 8) & 0xFF,
      blue: hex & 0xFF
    )
  }
  
  var uiColor: UIColor {
    return UIColor(self)
  }
}
