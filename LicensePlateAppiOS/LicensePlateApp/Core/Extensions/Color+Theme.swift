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
        
        // Accent Yellow: Slightly more vibrant in dark mode
        static let accentYellow = Color(
            light: Color(red: 0.96, green: 0.75, blue: 0.26),
            dark: Color(red: 1.0, green: 0.80, blue: 0.35)
        )
        
        // Soft Brown: Lighter beige in dark mode for readability
        static let softBrown = Color(
            light: Color(red: 0.58, green: 0.45, blue: 0.35),
            dark: Color(red: 0.75, green: 0.65, blue: 0.55)
        )
        
        // Card Background: Light gray -> Dark gray
        static let cardBackground = Color(
            light: Color(red: 0.87, green: 0.85, blue: 0.80),
            dark: Color(red: 0.18, green: 0.18, blue: 0.20)
        )
        
        // Permission Yellow: For "While App is Open" status
        // Light mode: More saturated/darker for visibility on light background
        // Dark mode: Bright yellow as provided
        static let permissionYellow = Color(//254,255,136, // original // light: Color(red: 0.85, green: 0.65, blue: 0.0), // not bad //light: Color(red: 0.85, green: 0.75, blue: 0.18),
          light: Color(red: 0.99, green: 1.0, blue: 0.53),
            dark: Color(red: 1.0, green: 0.84, blue: 0.0)
        )
        
        // Permission Orange: For "Not Set" status
        // Light mode: More saturated/darker for visibility on light background
        // Dark mode: Orange-red as provided
        static let permissionOrange = Color(
            light: Color(red: 0.85, green: 0.40, blue: 0.15),
            dark: Color(red: 1.0, green: 0.37, blue: 0.12)
        )
        
        // Permission Orange Dark: For location "Not Set" (slightly more red)
        // Light mode: More saturated/darker for visibility on light background
        // Dark mode: Red-orange as provided
        static let permissionOrangeDark = Color(
            light: Color(red: 0.85, green: 0.25, blue: 0.25),
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
