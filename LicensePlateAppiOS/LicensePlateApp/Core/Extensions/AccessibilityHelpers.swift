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
    
    /// Applies transition animation only if reduced motion is disabled
    func accessibleTransition(_ transition: AnyTransition) -> some View {
        Group {
            if UIAccessibility.isReduceMotionEnabled {
                self.transition(.opacity)
            } else {
                self.transition(transition)
            }
        }
    }
}

// MARK: - Animation Helpers

/// Helper function to perform animations that respect reduced motion settings
/// Use this instead of withAnimation() throughout the app
func withAccessibleAnimation<T>(
    _ animation: Animation? = .default,
    _ body: () throws -> T
) rethrows -> T {
    if UIAccessibility.isReduceMotionEnabled {
        // If reduced motion is enabled, perform without animation
        return try body()
    } else {
        // Otherwise, use the provided animation
        return try withAnimation(animation) {
            try body()
        }
    }
}

/// Helper function to perform animations that respect reduced motion settings (async version)
/// Note: withAnimation doesn't support async closures, so we execute the body first, then animate
func withAccessibleAnimation<T>(
    _ animation: Animation? = .default,
    _ body: @escaping () async throws -> T
) async rethrows -> T {
    if UIAccessibility.isReduceMotionEnabled {
        // If reduced motion is enabled, perform without animation
        return try await body()
    } else {
        // Execute the async body first, then apply animation to the result
        let result = try await body()
        // Note: withAnimation doesn't work with async, so we return the result
        // The animation will need to be handled at the view level
        return result
    }
}

