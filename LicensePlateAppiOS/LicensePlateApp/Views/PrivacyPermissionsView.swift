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
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    // Location Section
                    Section {
                        VStack(spacing: 12) {
                            PermissionRow(
                                title: "Location".localized,
                                icon: "location.fill",
                                status: locationPermissionStatus,
                                statusColor: locationPermissionColor,
                                onTap: openLocationSettings
                            )
                            
                            SettingToggleRow(
                                title: "Save location when marking plates".localized,
                                description: "Store location data when you mark a plate as found".localized,
                                isOn: $saveLocationWhenMarkingPlates
                            )
                            
                            SettingToggleRow(
                                title: "Show my location on large map".localized,
                                description: "Display your current location on the full-screen map".localized,
                                isOn: $showMyLocationOnLargeMap
                            )
                            
                            SettingToggleRow(
                                title: "Track my location during trips".localized,
                                description: "Continuously track your location while a trip is active (Can be disabled at any time)".localized,
                                isOn: $trackMyLocationDuringTrips
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Location".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    
                    // Voice Section
                    Section {
                        VStack(spacing: 12) {
                            PermissionRow(
                                title: "Microphone".localized,
                                icon: "mic.fill",
                                status: microphonePermissionStatus,
                                statusColor: microphonePermissionColor,
                                onTap: openMicrophoneSettings
                            )
                            
                            PermissionRow(
                                title: "Speech Recognizer".localized,
                                icon: "waveform",
                                status: speechRecognitionPermissionStatus,
                                statusColor: speechRecognitionPermissionColor,
                                onTap: openSpeechRecognitionSettings
                            )
                            
                            // Camera Permission (hidden for now)
                            if false {
                                PermissionRow(
                                    title: "Camera".localized,
                                    icon: "camera.fill",
                                    status: cameraPermissionStatus,
                                    statusColor: cameraPermissionColor,
                                    onTap: openCameraSettings
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Voice".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    
                    // Notifications Section
                    Section {
                        VStack(spacing: 12) {
                            PermissionRow(
                                title: "Notifications".localized,
                                icon: "bell.fill",
                                status: notificationPermissionStatus,
                                statusColor: notificationPermissionColor,
                                onTap: openNotificationSettings
                            )
                            
                            SettingToggleRow(
                                title: "Plate found by opponent".localized,
                                description: "Get notified when an opponent finds a plate".localized,
                                isOn: $notifyPlateFoundByOpponent
                            )
                            
                            SettingToggleRow(
                                title: "Plate found by co-pilots".localized,
                                description: "Get notified when a co-pilot finds a plate".localized,
                                isOn: $notifyPlateFoundByCoPilots
                            )
                            
                            SettingToggleRow(
                                title: "Promotion & News".localized,
                                description: "Receive promotional offers and app news".localized,
                                isOn: $notifyPromotionsAndNews
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Notifications".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Privacy & Permissions".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Closes this view".localized)
                }
            }
            .onAppear {
                checkPermissions()
            }
            .onChange(of: locationManager.authorizationStatus) { oldValue, newValue in
                checkPermissions()
            }
    }
    
    // Permission status helpers
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
    
    private var speechRecognitionPermissionStatus: String {
        switch speechRecognitionPermission {
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

