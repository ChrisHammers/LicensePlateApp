//
//  MainSettingsCoordinator.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import Combine

/// Coordinator for managing navigation in the Main Settings view
@MainActor
final class MainSettingsCoordinator: ObservableObject {
    enum SettingsDestination: Hashable {
        case profile
        case privacyPermissions
        case appPreferences
        case newTripDefaults
        case voiceDefaults
        case helpAbout
    }
    
    // MARK: - Navigation Methods
    
    /// Navigate to the Profile view
    func navigateToProfile(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.profile)
    }
    
    /// Navigate to the Privacy & Permissions view
    func navigateToPrivacyPermissions(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.privacyPermissions)
    }
    
    /// Navigate to the App Preferences view
    func navigateToAppPreferences(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.appPreferences)
    }
    
    /// Navigate to the New Trip Defaults view
    func navigateToNewTripDefaults(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.newTripDefaults)
    }
    
    /// Navigate to the Voice Defaults view
    func navigateToVoiceDefaults(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.voiceDefaults)
    }
    
    /// Navigate to the Help & About view
    func navigateToHelpAbout(path: Binding<NavigationPath>) {
        path.wrappedValue.append(SettingsDestination.helpAbout)
    }
    
    /// Navigate to a specific destination
    func navigate(to destination: SettingsDestination, path: Binding<NavigationPath>) {
        path.wrappedValue.append(destination)
    }
    
    /// Pop the current view from the navigation stack
    func pop(path: Binding<NavigationPath>) {
        if !path.wrappedValue.isEmpty {
            path.wrappedValue.removeLast()
        }
    }
    
    /// Pop to the root of the navigation stack
    func popToRoot(path: Binding<NavigationPath>) {
        path.wrappedValue.removeLast(path.wrappedValue.count)
    }
    
    /// Pop to a specific destination
    /// Note: NavigationPath doesn't provide direct access to its contents,
    /// so this implementation pops to root and navigates to the destination
    func popTo(_ destination: SettingsDestination, path: Binding<NavigationPath>) {
        popToRoot(path: path)
        navigate(to: destination, path: path)
    }
}

