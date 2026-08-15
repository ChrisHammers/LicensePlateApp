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
    var deferredSetupTouchSource: String = "legacy_onboarding"
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
                    Text("Join Family".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader("Join Family".localized)
                    
                    Text("onboarding.join_family.subtitle".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share Code".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        TextField("Enter share code".localized, text: $shareCode)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibleTextField(label: "Share Code".localized, hint: "Enter share code".localized, value: shareCode)
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
                                .accessibleDecorative()
                            Text("Scan QR Code".localized)
                        }
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                    }
                    .accessibleButton(label: "Scan QR Code".localized, hint: "Opens camera to scan QR code".localized)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            VStack(spacing: 20) {
                Button {
                    joinWithCode()
                } label: {
                    InviteActionLabel(
                        title: "Continue".localized,
                        isBusy: isJoining,
                        busyKind: .join
                    )
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
                .accessibleButton(
                    label: isJoining
                        ? InviteBusyKind.join.localizedBusyTitle
                        : "Continue".localized,
                    hint: "Continues to next screen".localized
                )
                .disabled(shareCode.isEmpty || isJoining || !authService.isOnline)
                .opacity((shareCode.isEmpty || isJoining || !authService.isOnline) ? 0.6 : 1)
                
                Button {
                    onNext()
                } label: {
                    Text("Skip".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .disabled(isJoining)
                .accessibleButton(label: "Skip".localized, hint: "Skips joining a family".localized)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            familyRepository.setModelContext(modelContext)
            DeferredProfileSetupStore.shared.markTouched(.family, source: deferredSetupTouchSource)
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView(scannedCode: $scannedCode)
        }
        .alert("Error".localized, isPresented: $showError) {
            Button("OK".localized, role: .cancel) { }
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
                    errorMessage = "Camera permission is required to scan QR codes".localized
                    showError = true
                }
            }
        }
    }
    
    private func joinWithCode() {
        let trimmedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isJoining = true
        errorMessage = nil
        
        Task {
            do {
                // COPPA F-18 (FR-60(b)): same consent-seeking sequence the join sheet runs —
                // mint → bind → declare, strictly before redeeming. No-op for adults.
                try await authService.provisionIdentityForConsentSeekingRedemptionIfNeeded()

                _ = try await familyRepository.redeemShareCode(code: trimmedCode, expectedType: .family)
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
