//
//  JoinFriendByCodeSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct JoinFriendByCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    private let inviteRepository = InviteRepository.shared
    @State private var shareCode = ""
    @State private var isRedeeming = false
    @State private var showQRScanner = false
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var redeemedInviteId: String?
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
                        Text("Enter a share code or scan a QR code to send a friend request".localized)
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
                
                if isRedeeming {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .navigationTitle("Add Friend by Code".localized)
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
                    Button("Send Request".localized) {
                        redeemCode()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(shareCode.isEmpty || isRedeeming || !authService.isOnline)
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
                    FriendInviteDetail(inviteId: inviteId)
                        .environmentObject(authService)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                inviteRepository.setModelContext(modelContext)
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
    
    private func redeemCode() {
        let trimmedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isRedeeming = true
        errorMessage = nil
        
        Task {
            do {
                let inviteId = try await familyRepository.redeemShareCode(code: trimmedCode)
                
                await MainActor.run {
                    isRedeeming = false
                    redeemedInviteId = inviteId
                    AnalyticsService.shared.log(.shareCodeUsed(type: "friend"))
                    // Show invite detail sheet
                    showInviteDetail = true
                }
            } catch {
                await MainActor.run {
                    isRedeeming = false
                    errorMessage = error.localizedDescription
                    showError = true
                    print("❌ Friend code redemption error: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    JoinFriendByCodeSheet()
        .environmentObject(FirebaseAuthService())
}

