//
//  OnboardingPermissionsView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import CoreLocation
import AVFoundation
import Speech
import UserNotifications

struct OnboardingPermissionsView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    @StateObject private var locationManager = LocationManager()
    @State private var microphonePermission: AVAudioSession.RecordPermission = .undetermined
    @State private var speechPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Permissions".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("These permissions help the app work better. You can enable them later in Settings.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        OnboardingPermissionRow(
                            title: "Location".localized,
                            description: "Show your position on the map, where you found a plate and track your trip".localized,
                            icon: "location.fill",
                            status: locationPermissionStatus,
                            statusColor: locationPermissionColor,
                            onTap: handleLocationTap
                        )
                        
                        OnboardingPermissionRow(
                            title: "Microphone".localized,
                            description: "Voice input for logging plates".localized,
                            icon: "mic.fill",
                            status: microphonePermissionStatus,
                            statusColor: microphonePermissionColor,
                            onTap: handleMicrophoneTap
                        )
                        
                        OnboardingPermissionRow(
                            title: "Speech Recognizer".localized,
                            description: "Understand spoken state names".localized,
                            icon: "waveform",
                            status: speechPermissionStatus,
                            statusColor: speechPermissionColor,
                            onTap: handleSpeechTap
                        )
                        
                        OnboardingPermissionRow(
                            title: "Camera".localized,
                            description: "Scan QR codes for Family and Friends".localized,
                            icon: "camera.fill",
                            status: cameraPermissionStatus,
                            statusColor: cameraPermissionColor,
                            onTap: handleCameraTap
                        )
                        
                        OnboardingPermissionRow(
                            title: "Notifications".localized,
                            description: "Get notified about plates found and more".localized,
                            icon: "bell.fill",
                            status: notificationPermissionStatus,
                            statusColor: notificationPermissionColor,
                            onTap: handleNotificationTap
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button {
                onNext()
            } label: {
                Text("Continue".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            checkPermissions()
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        microphonePermission = AVAudioSession.sharedInstance().recordPermission
        speechPermission = SFSpeechRecognizer.authorizationStatus()
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationPermission = settings.authorizationStatus
            }
        }
    }
    
    // Location
    private var locationPermissionStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "Allowed".localized
        case .authorizedWhenInUse:
            return "While App is Open".localized
        case .denied, .restricted:
            return "Disabled".localized
        case .notDetermined:
            return "Not Set".localized
        @unknown default:
            return "Unknown".localized
        }
    }
    
    private var locationPermissionColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return Color.Theme.permissionYellow
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrangeDark
        @unknown default:
            return Color.Theme.permissionOrangeDark
        }
    }
    
    private func handleLocationTap() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Allowed or While App is Open — open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notDetermined:
            locationManager.requestAuthorization()
        case .denied, .restricted:
            // Cannot re-show popup once denied — must open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // Microphone
    private var microphonePermissionStatus: String {
        switch microphonePermission {
        case .granted:
            return "Allowed".localized
        case .denied:
            return "Disabled".localized
        case .undetermined:
            return "Not Set".localized
        @unknown default:
            return "Unknown".localized
        }
    }
    
    private var microphonePermissionColor: Color {
        switch microphonePermission {
        case .granted:
            return .green
        case .denied:
            return .red
        case .undetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private func handleMicrophoneTap() {
        switch microphonePermission {
        case .granted:
            // Perfect allowed — open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .undetermined:
            // Show the permission popup
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    microphonePermission = granted ? .granted : .denied
                }
            }
        case .denied:
            // iOS won't re-show the popup once denied — must open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // Speech
    private var speechPermissionStatus: String {
        switch speechPermission {
        case .authorized:
            return "Allowed".localized
        case .denied, .restricted:
            return "Disabled".localized
        case .notDetermined:
            return "Not Set".localized
        @unknown default:
            return "Unknown".localized
        }
    }
    
    private var speechPermissionColor: Color {
        switch speechPermission {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    // Camera
    private var cameraPermissionStatus: String {
        switch cameraPermission {
        case .authorized:
            return "Allowed".localized
        case .denied, .restricted:
            return "Disabled".localized
        case .notDetermined:
            return "Not Set".localized
        @unknown default:
            return "Unknown".localized
        }
    }
    
    private var cameraPermissionColor: Color {
        switch cameraPermission {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private func handleCameraTap() {
        switch cameraPermission {
        case .authorized:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func handleSpeechTap() {
        switch speechPermission {
        case .authorized:
            // Perfect allowed — open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notDetermined:
            // Show the permission popup
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    speechPermission = status
                }
            }
        case .denied, .restricted:
            // iOS won't re-show the popup once denied — must open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // Notifications
    private var notificationPermissionStatus: String {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return "Allowed".localized
        case .denied:
            return "Disabled".localized
        case .notDetermined:
            return "Not Set".localized
        @unknown default:
            return "Unknown".localized
        }
    }
    
    private var notificationPermissionColor: Color {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private func handleNotificationTap() {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            // Perfect allowed — open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notDetermined:
            // Show the permission popup
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                await MainActor.run {
                    checkPermissions()
                }
            }
        case .denied:
            // iOS won't re-show the popup once denied — must open Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let status: String
    let statusColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(description)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                
                Spacer()
                
                Text(status)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                
                if statusColor != .green {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .padding()
            .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
