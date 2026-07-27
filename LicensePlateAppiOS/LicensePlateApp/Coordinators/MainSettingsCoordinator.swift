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
        case friends
        case family
        case achievements
        case rankProgression
//        case deferredProfileSetup
    }
  
    @Published var path = NavigationPath()
  
    // MARK: - Navigation Methods
    
    /// Navigate to the Profile view
    func navigateToProfile() {
        path.append(SettingsDestination.profile)
      
    print("pathProfile: \(path.count)")
    
    }
    
    /// Navigate to the Privacy & Permissions view
    func navigateToPrivacyPermissions() {
        path.append(SettingsDestination.privacyPermissions)
    }
    
    /// Navigate to the App Preferences view
    func navigateToAppPreferences() {
        path.append(SettingsDestination.appPreferences)
    }
    
    /// Navigate to the New Trip/Game Defaults view
    func navigateToNewTripDefaults() {
        path.append(SettingsDestination.newTripDefaults)
    }
    
    /// Navigate to the Voice Defaults view
    func navigateToVoiceDefaults() {
        path.append(SettingsDestination.voiceDefaults)
    }
    
    /// Navigate to the Help & About view
    func navigateToHelpAbout() {
        path.append(SettingsDestination.helpAbout)
    }
    
    /// Navigate to the Friends view
    func navigateToFriends() {
        path.append(SettingsDestination.friends)
      print("pathFriends: \(path.count)")
        }
    
    /// Navigate to the Family view
    func navigateToFamily() {
        path.append(SettingsDestination.family)
    }
    
    /// Navigate to the Achievements view
    func navigateToAchievements() {
        path.append(SettingsDestination.achievements)
    }
    
    /// Navigate to deferred profile setup hub
//    func navigateToDeferredProfileSetup() {
//        path.append(SettingsDestination.deferredProfileSetup)
//    }

    /// Navigate to the Rank Progression view
    func navifateToRankProgression() {
        path.append(SettingsDestination.rankProgression)
    }
        
    /// Navigate to a specific destination
    func navigate(to destination: SettingsDestination) {
        path.append(destination)
    }
    
    /// Pop the current view from the navigation stack
    func pop() {
      
    print("pathPop: \(path.count)")
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    /// Pop to the root of the navigation stack
    func popToRoot() {
        path.removeLast(path.count)
    }
    
    /// Pop to a specific destination
    /// Note: NavigationPath doesn't provide direct access to its contents,
    /// so this implementation pops to root and navigates to the destination
    func popTo(_ destination: SettingsDestination) {
        popToRoot()
        navigate(to: destination)
    }
}

