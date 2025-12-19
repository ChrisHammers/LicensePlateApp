//
//  JoinFamilySheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct JoinFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    private let inviteRepository = InviteRepository.shared
    @State private var shareCode = ""
    @State private var isJoining = false
    @State private var showQRScanner = false
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var redeemedInviteId: String?
    @State private var redeemedFamilyId: String?
    @State private var showInviteDetail = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        TextField("Enter Share Code".localized, text: $shareCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: scannedCode) { oldValue, newValue in
                                if let code = newValue {
                                    shareCode = extractCode(from: code)
                                }
                            }
                    } header: {
                        Text("Share Code".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    } footer: {
                        Text("Enter a share code or scan a QR code to join a family".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    Section {
                        Button {
                            requestCameraPermissionAndScan()
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                Text("Scan QR Code".localized)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                        }
                    }
                    
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.caption, design: .rounded))
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle("Join Family".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join".localized) {
                        joinWithCode()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(shareCode.isEmpty || isJoining || !authService.isOnline)
                }
            }
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(scannedCode: $scannedCode)
            }
            .sheet(isPresented: $showInviteDetail) {
                if let inviteId = redeemedInviteId {
                    FamilyInviteDetail(inviteId: inviteId, familyId: redeemedFamilyId ?? "", family: nil)
                        .environmentObject(authService)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                inviteRepository.setModelContext(modelContext)
                AnalyticsService.shared.log(.familyJoinCTATapped)
            }
        }
    }
    
    private func extractCode(from scannedString: String) -> String {
        // If it's a deep link URL, extract the code from query params
        if let url = URL(string: scannedString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let codeItem = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return codeItem
        }
        
        // If it's just a code, return as-is
        return scannedString
    }
    
    private func requestCameraPermissionAndScan() {
        Task {
            let hasPermission = await QRCodeService.shared.requestCameraPermission()
            if hasPermission {
                await MainActor.run {
                    showQRScanner = true
                }
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
                let inviteId = try await familyRepository.redeemShareCode(code: trimmedCode)
                
                // Fetch the invite from Firestore to get familyId
                let familyId = try? await familyRepository.getFamilyIdFromInvite(inviteId: inviteId)
                
                await MainActor.run {
                    isJoining = false
                    redeemedInviteId = inviteId
                    redeemedFamilyId = familyId
                    AnalyticsService.shared.log(.familyJoinCodeRedeemed)
                    // Show invite detail sheet
                    showInviteDetail = true
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = error.localizedDescription
                    showError = true
                    AnalyticsService.shared.log(.familyJoinFailed(error: error.localizedDescription))
                }
            }
        }
    }
}

#Preview {
    JoinFamilySheet()
        .environmentObject(FirebaseAuthService())
}

