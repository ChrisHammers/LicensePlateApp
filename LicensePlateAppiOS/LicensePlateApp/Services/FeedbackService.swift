import Foundation
import UIKit
import AudioToolbox
import SwiftUI

/// Service for providing haptic and sound feedback throughout the app
class FeedbackService {
    nonisolated(unsafe) static let shared = FeedbackService()
    
    // User preferences (will be injected from views)
    var hapticEnabled: Bool = true
    var soundEnabled: Bool = true
    
    // Haptic generators (lazy to avoid creating them if not needed)
    private lazy var lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private lazy var mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private lazy var heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        // Prepare generators for immediate use
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    /// Update preferences from AppStorage values
    @MainActor
    func updatePreferences(hapticEnabled: Bool, soundEnabled: Bool) {
        self.hapticEnabled = hapticEnabled
        self.soundEnabled = soundEnabled
    }
    
    // MARK: - Haptic Feedback
    
    /// Light haptic feedback for subtle interactions
    @MainActor
    func lightImpact() {
        guard hapticEnabled else { return }
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare() // Prepare for next use
    }
    
    /// Medium haptic feedback for standard button taps
    @MainActor
    func mediumImpact() {
        guard hapticEnabled else { return }
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }
    
    /// Heavy haptic feedback for important actions
    @MainActor
    func heavyImpact() {
        guard hapticEnabled else { return }
        heavyImpactGenerator.impactOccurred()
        heavyImpactGenerator.prepare()
    }
    
    /// Selection haptic feedback for picker/selection changes
    @MainActor
    func selection() {
        guard hapticEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
    
    /// Success notification haptic feedback
    @MainActor
    func success() {
        guard hapticEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }
    
    /// Warning notification haptic feedback
    @MainActor
    func warning() {
        guard hapticEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
    
    /// Error notification haptic feedback
    @MainActor
    func error() {
        guard hapticEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
    
    // MARK: - Sound Feedback
    
    /// Play a system sound
    /// - Parameter soundID: System sound ID (see AudioToolbox for available sounds)
    @MainActor
    func playSystemSound(_ soundID: SystemSoundID) {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(soundID)
    }
    
    /// Play a tap/click sound
    @MainActor
    func tap() {
        guard soundEnabled else { return }
        // System sound for tap/click
        AudioServicesPlaySystemSound(1104) // Tink sound
    }
    
    /// Play a success sound
    @MainActor
    func successSound() {
        guard soundEnabled else { return }
        // System sound for success
        AudioServicesPlaySystemSound(1057) // Success/alert sound
    }
    
    /// Play an error sound
    @MainActor
    func errorSound() {
        guard soundEnabled else { return }
        // System sound for error
        AudioServicesPlaySystemSound(1053) // Error/alert sound
    }
    
    /// Play a recording start sound
    @MainActor
    func recordingStart() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1057) // Recording start sound
    }
    
    // MARK: - Combined Feedback
    
    /// Combined haptic and sound feedback for button taps
    @MainActor
    func buttonTap() {
        mediumImpact()
        tap()
    }
    
    /// Combined feedback for successful actions
    @MainActor
    func actionSuccess() {
        success()
        successSound()
    }
    
    /// Combined feedback for errors
    @MainActor
    func actionError() {
        error()
        errorSound()
    }
    
    /// Combined feedback for selection changes
    @MainActor
    func selectionChange() {
        selection()
        //tap()
    }
    
    /// Combined feedback for toggling a region/plate
    @MainActor
    func toggleRegion() {
        lightImpact()
        tap()
    }
    
    /// Combined feedback for starting recording
    @MainActor
    func startRecording() {
        mediumImpact()
        recordingStart()
    }
}

