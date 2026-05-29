//
//  CreateFriendShareCodeSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct CreateFriendShareCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel = CreateFriendShareCodeViewModel()

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if viewModel.isGenerating {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let code = viewModel.shareCode {
                    ScrollView {
                        VStack(spacing: 24) {
                            VStack(spacing: 12) {
                                Text("Your Share Code".localized)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)

                                Text(code)
                                    .font(.system(.largeTitle, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .padding()
                                    .background(Color.Theme.cardBackground)
                                    .cornerRadius(12)

                                if let expiresAt = viewModel.expiresAt {
                                    Text("Expires in \(viewModel.timeUntilExpiration(expiresAt))".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.Theme.cardBackground)
                            .cornerRadius(16)

                            if let qrImage = viewModel.qrCodeImage {
                                VStack(spacing: 12) {
                                    Text("QR Code".localized)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)

                                    Image(uiImage: qrImage)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .background(Color.white)
                                        .cornerRadius(12)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.Theme.cardBackground)
                                .cornerRadius(16)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("How to share".localized)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)

                                Text("Share this code or QR code with a friend. They can enter it in the Friends section to send you a friend request.".localized)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.Theme.cardBackground)
                            .cornerRadius(16)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Generate a share code to invite friends".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)
                            .padding()

                        Button("Generate Code".localized) {
                            viewModel.generateCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.Theme.primaryBlue)
                        .disabled(!authService.isOnline)
                    }
                    .padding()
                }
            }
            .navigationTitle("Create Share Code".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        dismiss()
                    }
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
                if viewModel.shareCode == nil {
                    viewModel.generateCode()
                }
            }
        }
    }
}

#Preview {
    CreateFriendShareCodeSheet()
        .environmentObject(FirebaseAuthService())
}
