//
//  PrivacyPermissionsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import CoreLocation
import AVFoundation
import UserNotifications
import Speech

struct PrivacyPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Privacy & Permissions
    @AppStorage("saveLocationWhenMarkingPlates") private var saveLocationWhenMarkingPlates = true
    @AppStorage("showMyLocationOnLargeMap") private var showMyLocationOnLargeMap = true
    @AppStorage("trackMyLocationDuringTrips") private var trackMyLocationDuringTrips = true
    @AppStorage("notifyPlateFoundByOpponent") private var notifyPlateFoundByOpponent = true
    @AppStorage("notifyPlateFoundByCoPilots") private var notifyPlateFoundByCoPilots = true
    @AppStorage("notifyPromotionsAndNews") private var notifyPromotionsAndNews = false
    
    @StateObject private var locationManager = LocationManager()
    @State private var microphonePermission: AVAudioSession.RecordPermission = .undetermined
    @State private var speechRecognitionPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 12) {
                            // Location Permission
                            PermissionRow(
                                title: "Location",
                                icon: "location.fill",
                                status: locationPermissionStatus,
                                statusColor: locationPermissionColor,
                                onTap: openLocationSettings
                            )
                            
                            SettingToggleRow(
                                title: "Save location when marking plates",
                                description: "Store location data when you mark a plate as found",
                                isOn: $saveLocationWhenMarkingPlates
                            )
                            
                            SettingToggleRow(
                                title: "Show my location on large map",
                                description: "Display your current location on the full-screen map",
                                isOn: $showMyLocationOnLargeMap
                            )
                            
                            SettingToggleRow(
                                title: "Track my location during trips",
                                description: "Continuously track your location while a trip is active (Can be disabled at any time)",
                                isOn: $trackMyLocationDuringTrips
                            )
                          
                            Divider()
                            
                            // Microphone Permission
                            PermissionRow(
                                title: "Microphone",
                                icon: "mic.fill",
                                status: microphonePermissionStatus,
                                statusColor: microphonePermissionColor,
                                onTap: openMicrophoneSettings
                            )
                          
                            Divider()
                            
                            // Speech Recognizer Permission
                            PermissionRow(
                                title: "Speech Recognizer",
                                icon: "waveform",
                                status: speechRecognitionPermissionStatus,
                                statusColor: speechRecognitionPermissionColor,
                                onTap: openSpeechRecognitionSettings
                            )
                          
                            Divider()
                            
                            // Camera Permission (hidden for now)
                            if false {
                                PermissionRow(
                                    title: "Camera",
                                    icon: "camera.fill",
                                    status: cameraPermissionStatus,
                                    statusColor: cameraPermissionColor,
                                    onTap: openCameraSettings
                                )
                              
                                Divider()
                            }
                            
                            // Notifications Permission
                            PermissionRow(
                                title: "Notifications",
                                icon: "bell.fill",
                                status: notificationPermissionStatus,
                                statusColor: notificationPermissionColor,
                                onTap: openNotificationSettings
                            )
                            
                            SettingToggleRow(
                                title: "Plate found by opponent",
                                description: "Get notified when an opponent finds a plate",
                                isOn: $notifyPlateFoundByOpponent
                            )
                            
                            SettingToggleRow(
                                title: "Plate found by co-pilots",
                                description: "Get notified when a co-pilot finds a plate",
                                isOn: $notifyPlateFoundByCoPilots
                            )
                            
                            SettingToggleRow(
                                title: "Promotion & News",
                                description: "Receive promotional offers and app news",
                                isOn: $notifyPromotionsAndNews
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    }
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Privacy & Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .onAppear {
                checkPermissions()
            }
            .onChange(of: locationManager.authorizationStatus) { oldValue, newValue in
                checkPermissions()
            }
        }
    }
    
    // Permission status helpers
    private var locationPermissionStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "Allowed"
        case .authorizedWhenInUse:
            return "While App is Open"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
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
    
    private var microphonePermissionStatus: String {
        switch microphonePermission {
        case .granted:
            return "Allowed"
        case .denied:
            return "Disabled"
        case .undetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
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
    
    private var speechRecognitionPermissionStatus: String {
        switch speechRecognitionPermission {
        case .authorized:
            return "Allowed"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var speechRecognitionPermissionColor: Color {
        switch speechRecognitionPermission {
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
    
    private var cameraPermissionStatus: String {
        switch cameraPermission {
        case .authorized:
            return "Allowed"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
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
    
    private var notificationPermissionStatus: String {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
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
    
    private func checkPermissions() {
        // Check microphone permission
        microphonePermission = AVAudioSession.sharedInstance().recordPermission
        
        // Check speech recognition permission
        speechRecognitionPermission = SFSpeechRecognizer.authorizationStatus()
        
        // Check camera permission
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        
        // Check notification permission
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationPermission = settings.authorizationStatus
            }
        }
    }
    
    private func openLocationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openMicrophoneSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openSpeechRecognitionSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openCameraSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let title: String
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
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
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

