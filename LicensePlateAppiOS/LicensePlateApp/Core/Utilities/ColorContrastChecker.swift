//
//  ColorContrastChecker.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import UIKit

/// Utility for checking WCAG color contrast compliance
struct ColorContrastChecker {
    
    // MARK: - WCAG Standards
    enum WCAGLevel {
        case AA
        case AAA
        
        var normalTextRatio: Double {
            switch self {
            case .AA: return 4.5
            case .AAA: return 7.0
            }
        }
        
        var largeTextRatio: Double {
            switch self {
            case .AA: return 3.0
            case .AAA: return 4.5
            }
        }
        
        var uiComponentRatio: Double {
            switch self {
            case .AA: return 3.0
            case .AAA: return 3.0
            }
        }
    }
    
    // MARK: - Contrast Result
    struct ContrastResult {
        let ratio: Double
        let passesNormalText: Bool
        let passesLargeText: Bool
        let passesUIComponent: Bool
        let level: WCAGLevel
        
        var status: String {
            if passesNormalText {
                return "✅ Passes WCAG \(level) (Normal & Large Text)"
            } else if passesLargeText {
                return "⚠️ Passes WCAG \(level) (Large Text Only)"
            } else {
                return "❌ Fails WCAG \(level)"
            }
        }
    }
    
    // MARK: - Calculate Relative Luminance
    /// Calculates the relative luminance of a color (0.0 to 1.0)
    /// Based on WCAG 2.1 formula
    static func relativeLuminance(_ color: UIColor) -> Double {
        let rgb = color.rgbComponents
        
        // Convert to linear RGB
        func linearize(_ component: Double) -> Double {
            if component <= 0.03928 {
                return component / 12.92
            } else {
                return pow((component + 0.055) / 1.055, 2.4)
            }
        }
        
        let r = linearize(rgb.red)
        let g = linearize(rgb.green)
        let b = linearize(rgb.blue)
        
        // Calculate relative luminance
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    // MARK: - Calculate Contrast Ratio
    /// Calculates the contrast ratio between two colors
    /// Returns a value from 1.0 (no contrast) to 21.0 (maximum contrast)
    static func contrastRatio(_ color1: UIColor, _ color2: UIColor) -> Double {
        let l1 = relativeLuminance(color1)
        let l2 = relativeLuminance(color2)
        
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    // MARK: - Check WCAG Compliance
    /// Checks if a color combination meets WCAG standards
    static func checkContrast(
        foreground: UIColor,
        background: UIColor,
        level: WCAGLevel = .AA
    ) -> ContrastResult {
        let ratio = contrastRatio(foreground, background)
        
        return ContrastResult(
            ratio: ratio,
            passesNormalText: ratio >= level.normalTextRatio,
            passesLargeText: ratio >= level.largeTextRatio,
            passesUIComponent: ratio >= level.uiComponentRatio,
            level: level
        )
    }
    
    // MARK: - Check SwiftUI Color
    /// Convenience method for SwiftUI Color
    static func checkContrast(
        foreground: Color,
        background: Color,
        level: WCAGLevel = .AA
    ) -> ContrastResult {
        let foregroundUI = UIColor(foreground)
        let backgroundUI = UIColor(background)
        return checkContrast(foreground: foregroundUI, background: backgroundUI, level: level)
    }
    
    // MARK: - Find Accessible Color
    /// Finds a darker/lighter version of a color that meets WCAG AA contrast
    /// Returns the adjusted color and the achieved contrast ratio
    static func findAccessibleColor(
        foreground: UIColor,
        background: UIColor,
        targetRatio: Double = 4.5,
        maxIterations: Int = 20
    ) -> (color: UIColor, ratio: Double)? {
        var currentColor = foreground
        var currentRatio = contrastRatio(currentColor, background)
        
        // If already meets target, return original
        if currentRatio >= targetRatio {
            return (currentColor, currentRatio)
        }
        
        // Determine if we need to darken or lighten
        let foregroundLum = relativeLuminance(foreground)
        let backgroundLum = relativeLuminance(background)
        let shouldDarken = foregroundLum > backgroundLum
        
        var rgb = currentColor.rgbComponents
        let step: Double = shouldDarken ? -0.02 : 0.02
        
        for _ in 0..<maxIterations {
            // Adjust RGB components
            rgb.red = max(0, min(1, rgb.red + step))
            rgb.green = max(0, min(1, rgb.green + step))
            rgb.blue = max(0, min(1, rgb.blue + step))
            
            let newColor = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
            let newRatio = contrastRatio(newColor, background)
            
            if newRatio >= targetRatio {
                return (newColor, newRatio)
            }
            
            currentColor = newColor
            currentRatio = newRatio
        }
        
        return nil
    }
}

// MARK: - UIColor Extensions
extension UIColor {
    var rgbComponents: (red: Double, green: Double, blue: Double, alpha: Double) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - Debug Helper
extension ColorContrastChecker {
    /// Prints a detailed contrast report for debugging
    static func printContrastReport(
        foreground: Color,
        background: Color,
        name: String = "Color Combination"
    ) {
        let result = checkContrast(foreground: foreground, background: background)
        
        print("""
        📊 \(name)
        ──────────────────────────────────────
        Contrast Ratio: \(String(format: "%.2f", result.ratio)):1
        \(result.status)
        ──────────────────────────────────────
        """)
    }
}

