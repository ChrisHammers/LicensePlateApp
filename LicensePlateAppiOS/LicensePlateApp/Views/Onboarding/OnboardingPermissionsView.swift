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

struct OnboardingPermissionsView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    @StateObject private var locationManager = LocationManager()
    @State private var microphonePermission: AVAudioSession.RecordPermission = .undetermined
    @State private var speechPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Permissions")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("These permissions help the app work better. You can enable them later in Settings.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        PermissionRow(
                            title: "Location",
                            description: "Show your position on the map",
                            status: locationStatusText,
                            onAllow: requestLocation,
                            onSkip: { }
                        )
                        
                        PermissionRow(
                            title: "Microphone",
                            description: "Voice input for logging plates",
                            status: microphoneStatusText,
                            onAllow: requestMicrophone,
                            onSkip: { }
                        )
                        
                        PermissionRow(
                            title: "Speech Recognition",
                            description: "Understand spoken state names",
                            status: speechStatusText,
                            onAllow: requestSpeech,
                            onSkip: { }
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
                Text("Continue")
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
            microphonePermission = AVAudioSession.sharedInstance().recordPermission
            speechPermission = SFSpeechRecognizer.authorizationStatus()
        }
    }
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not set"
        }
    }
    
    private var microphoneStatusText: String {
        switch microphonePermission {
        case .granted: return "Allowed"
        case .denied: return "Denied"
        default: return "Not set"
        }
    }
    
    private var speechStatusText: String {
        switch speechPermission {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not set"
        }
    }
    
    private func requestLocation() {
        locationManager.requestAuthorization()
    }
    
    private func requestMicrophone() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            Task { @MainActor in
                microphonePermission = granted ? .granted : .denied
            }
        }
    }
    
    private func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                speechPermission = status
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let status: String
    let onAllow: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            HStack(spacing: 12) {
                Button {
                    onAllow()
                } label: {
                    Text("Allow")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.Theme.primaryBlue)
                        )
                        .foregroundStyle(.white)
                }
                
                Button {
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.system(.caption, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
        }
        .padding()
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
