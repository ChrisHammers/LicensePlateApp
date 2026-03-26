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
    @StateObject private var viewModel = JoinFriendByCodeViewModel()
    @State private var showQRScanner = false
    @State private var scannedCode: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                Form {
                    Section {
                        TextField("Enter Share Code".localized, text: $viewModel.shareCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: scannedCode) { _, newValue in
                                if let code = newValue {
                                    viewModel.shareCode = extractCode(from: code)
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

                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.caption, design: .rounded))
                        }
                    }
                }
                .formStyle(.grouped)

                if viewModel.isRedeeming {
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
                        viewModel.redeemCode()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(viewModel.shareCode.isEmpty || viewModel.isRedeeming || !authService.isOnline)
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(scannedCode: $scannedCode)
            }
            .sheet(isPresented: $viewModel.showInviteDetail) {
                if let inviteId = viewModel.redeemedInviteId {
                    FriendInviteDetail(inviteId: inviteId)
                        .environmentObject(authService)
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
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
                await MainActor.run {
                    showQRScanner = true
                }
            } else {
                await MainActor.run {
                    viewModel.errorMessage = "Camera permission is required to scan QR codes".localized
                    viewModel.showError = true
                }
            }
        }
    }
}

#Preview {
    JoinFriendByCodeSheet()
        .environmentObject(FirebaseAuthService())
}
