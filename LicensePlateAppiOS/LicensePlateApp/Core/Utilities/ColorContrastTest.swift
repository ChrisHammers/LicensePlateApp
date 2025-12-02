//
//  ColorContrastTest.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//
//  This file can be used to test color contrast during development
//  Run these tests in a playground or add to your app's debug menu

import SwiftUI

#if DEBUG
struct ColorContrastTest {
    static func runAllTests() {
        print("🎨 Running Color Contrast Tests...")
        print("=" * 60)
        
        // Test Light Mode Colors
        testLightMode()
        
        // Test Dark Mode Colors
        testDarkMode()
        
        print("=" * 60)
        print("✅ Tests Complete")
    }
    
    static func testLightMode() {
        print("\n📱 LIGHT MODE")
        print("-" * 60)
        
        let background = Color(red: 0.95, green: 0.94, blue: 0.90)
        let cardBackground = Color(red: 0.87, green: 0.85, blue: 0.80)
        let primaryBlue = Color(red: 0.18, green: 0.44, blue: 0.64)
        let softBrown = Color(red: 0.39, green: 0.29, blue: 0.22) // Updated value
        let accentYellow = Color(red: 0.96, green: 0.75, blue: 0.26)
        let white = Color.white
        
        // Primary Blue on Background
        ColorContrastChecker.printContrastReport(
            foreground: primaryBlue,
            background: background,
            name: "Primary Blue on Background (Light)"
        )
        
        // Soft Brown on Background
        ColorContrastChecker.printContrastReport(
            foreground: softBrown,
            background: background,
            name: "Soft Brown on Background (Light)"
        )
        
        // Primary Blue on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: primaryBlue,
            background: cardBackground,
            name: "Primary Blue on Card Background (Light)"
        )
        
        // Soft Brown on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: softBrown,
            background: cardBackground,
            name: "Soft Brown on Card Background (Light)"
        )
        
        // White on Primary Blue (buttons)
        ColorContrastChecker.printContrastReport(
            foreground: white,
            background: primaryBlue,
            name: "White on Primary Blue (Light)"
        )
        
        // Accent Yellow on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: accentYellow,
            background: cardBackground,
            name: "Accent Yellow on Card Background (Light)"
        )
        
        // Accent Yellow on Background
        ColorContrastChecker.printContrastReport(
            foreground: accentYellow,
            background: background,
            name: "Accent Yellow on Background (Light)"
        )
    }
    
    static func testDarkMode() {
        print("\n🌙 DARK MODE")
        print("-" * 60)
        
        let background = Color(red: 0.11, green: 0.11, blue: 0.12)
        let cardBackground = Color(red: 0.18, green: 0.18, blue: 0.20)
        let primaryBlue = Color(red: 0.35, green: 0.60, blue: 0.80)
        let softBrown = Color(red: 0.75, green: 0.65, blue: 0.55)
        let accentYellow = Color(red: 1.0, green: 0.80, blue: 0.35)
        let white = Color.white
        
        // Primary Blue on Background
        ColorContrastChecker.printContrastReport(
            foreground: primaryBlue,
            background: background,
            name: "Primary Blue on Background (Dark)"
        )
        
        // Soft Brown on Background
        ColorContrastChecker.printContrastReport(
            foreground: softBrown,
            background: background,
            name: "Soft Brown on Background (Dark)"
        )
        
        // Primary Blue on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: primaryBlue,
            background: cardBackground,
            name: "Primary Blue on Card Background (Dark)"
        )
        
        // Soft Brown on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: softBrown,
            background: cardBackground,
            name: "Soft Brown on Card Background (Dark)"
        )
        
        // White on Primary Blue (buttons)
        ColorContrastChecker.printContrastReport(
            foreground: white,
            background: primaryBlue,
            name: "White on Primary Blue (Dark)"
        )
        
        // Accent Yellow on Card Background
        ColorContrastChecker.printContrastReport(
            foreground: accentYellow,
            background: cardBackground,
            name: "Accent Yellow on Card Background (Dark)"
        )
        
        // Accent Yellow on Background
        ColorContrastChecker.printContrastReport(
            foreground: accentYellow,
            background: background,
            name: "Accent Yellow on Background (Dark)"
        )
    }
}

// Helper for string repetition
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
#endif

