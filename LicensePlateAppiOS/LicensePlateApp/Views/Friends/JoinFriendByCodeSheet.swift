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
            AppBackgroundView {
                Form {
                    Section {
                        TextField("Enter Share Code".localized, text: $viewModel.shareCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibleTextField(
                                label: "Share Code".localized,
                                hint: "Enter a share code or scan a QR code to send a friend request".localized,
                                value: viewModel.shareCode
                            )
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
                    .listRowBackground(Color.Theme.cardBackground)

                    Section {
                        Button {
                            viewModel.requestCameraPermissionAndScan {
                                showQRScanner = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .accessibleDecorative()
                                Text("Scan QR Code".localized)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                        }
                        .accessibleButton(
                            label: "Scan QR Code".localized,
                            hint: "Opens camera to scan QR code".localized
                        )
                    }
                    .listRowBackground(Color.Theme.cardBackground)

                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.caption, design: .rounded))
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .disabled(viewModel.isRedeeming)
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
                    .disabled(viewModel.isRedeeming)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.redeemCode()
                    } label: {
                        InviteActionLabel(
                            title: "Send Request".localized,
                            isBusy: viewModel.isRedeeming,
                            busyKind: .send
                        )
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(viewModel.shareCode.isEmpty || viewModel.isRedeeming || !authService.isOnline)
                    .accessibleButton(
                        label: viewModel.isRedeeming
                            ? InviteBusyKind.send.localizedBusyTitle
                            : "Send Request".localized
                    )
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
                viewModel.onAppear()
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
}

#Preview {
    JoinFriendByCodeSheet()
        .environmentObject(FirebaseAuthService())
}
