//
//  AccessibilityHelpers.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

// MARK: - Accessibility Extensions

extension View {
    /// Makes a view accessible as a button with label and optional hint
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint ?? "")
    }
    
    /// Makes a toggle accessible with label and on/off state
    func accessibleToggle(label: String, isOn: Bool, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint ?? "")
    }
    
    /// Makes a navigation link accessible
    func accessibleNavigationLink(label: String, description: String? = nil) -> some View {
        var fullLabel = label
        if let description = description {
            fullLabel += ", \(description)"
        }
        return self
            .accessibilityLabel(fullLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to open")
    }
    
    /// Makes a text field accessible
    func accessibleTextField(label: String, hint: String? = nil, value: String? = nil) -> some View {
        var accessibilityValue = ""
        if let value = value, !value.isEmpty {
            accessibilityValue = value
        }
        return self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "Enter text")
            .accessibilityValue(accessibilityValue)
    }
    
    /// Makes a status indicator accessible
    func accessibleStatus(label: String, value: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(.isStaticText)
    }
    
    /// Hides decorative elements from accessibility
    func accessibleHiddenIfDecorative(_ isDecorative: Bool = true) -> some View {
        self.accessibilityHidden(isDecorative)
    }
}

// MARK: - Accessibility Announcements

extension View {
    /// Announces a message to VoiceOver users
    func announceToAccessibility(_ message: String) -> some View {
        self.onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }
}

// MARK: - Dynamic Type Support

extension View {
    /// Ensures text scales with Dynamic Type
    func supportsDynamicType() -> some View {
        self
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - Reduced Motion Support

extension View {
    /// Applies animation only if reduced motion is disabled
    func accessibleAnimation<T: Equatable>(_ animation: Animation, value: T) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            return self.animation(nil, value: value)
        } else {
            return self.animation(animation, value: value)
        }
    }
}

