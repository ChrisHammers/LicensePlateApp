//
//  OnboardingJoinFamilyView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import SwiftData

struct OnboardingJoinFamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    private let familyRepository = FamilyRepository.shared
    
    @State private var shareCode = ""
    @State private var isJoining = false
    @State private var showQRScanner = false
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Join Family")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Scouts need to join a family. Enter the share code from your Captain.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share Code")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        TextField("Enter share code", text: $shareCode)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: scannedCode) { _, newValue in
                                if let code = newValue {
                                    shareCode = extractCode(from: code)
                                }
                            }
                    }
                    .padding()
                    .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    Button {
                        requestCameraPermissionAndScan()
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                        }
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button("Continue") {
                joinWithCode()
            }
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.Theme.primaryBlue, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .disabled(shareCode.isEmpty || isJoining || !authService.isOnline)
            .opacity((shareCode.isEmpty || isJoining || !authService.isOnline) ? 0.6 : 1)
        }
        .onAppear {
            familyRepository.setModelContext(modelContext)
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView(scannedCode: $scannedCode)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    private func extractCode(from scannedString: String) -> String {
        if let url = URL(string: scannedString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let codeItem = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return codeItem
        }
        return scannedString
    }
    
    private func requestCameraPermissionAndScan() {
        Task {
            let hasPermission = await QRCodeService.shared.requestCameraPermission()
            if hasPermission {
                await MainActor.run { showQRScanner = true }
            } else {
                await MainActor.run {
                    errorMessage = "Camera permission is required to scan QR codes"
                    showError = true
                }
            }
        }
    }
    
    private func joinWithCode() {
        let trimmedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        guard authService.isOnline else {
            errorMessage = "Requires network connection"
            showError = true
            return
        }
        
        isJoining = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await familyRepository.redeemShareCode(code: trimmedCode)
                await MainActor.run {
                    isJoining = false
                    onNext()
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
