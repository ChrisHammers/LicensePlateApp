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
    @StateObject private var viewModel = JoinFamilyViewModel()

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
                                hint: "Enter a share code or scan a QR code to join a family".localized,
                                value: viewModel.shareCode
                            )
                            .onChange(of: viewModel.scannedCode) { _, newValue in
                                if let code = newValue {
                                    viewModel.applyScannedCode(code)
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
                    .listRowBackground(Color.Theme.cardBackground)

                    Section {
                        Button {
                            viewModel.requestCameraPermissionAndScan()
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
                        viewModel.joinWithCode()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(viewModel.shareCode.isEmpty || viewModel.isJoining || !authService.isOnline)
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $viewModel.showQRScanner) {
                QRScannerView(scannedCode: $viewModel.scannedCode)
            }
            .sheet(isPresented: $viewModel.showInviteDetail) {
                if let inviteId = viewModel.redeemedInviteId {
                    FamilyInviteDetail(
                        inviteId: inviteId,
                        familyId: viewModel.redeemedFamilyId ?? "",
                        family: nil
                    )
                    .environmentObject(authService)
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
                viewModel.onAppear()
            }
        }
    }
}

#Preview {
    JoinFamilySheet()
        .environmentObject(FirebaseAuthService())
}
