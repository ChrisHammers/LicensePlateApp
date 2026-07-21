//
//  CreateFamilyShareCodeSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData
import UIKit
import Combine

struct CreateFamilyShareCodeSheet: View {
    let familyId: String
    let existingShareCode: ShareCode?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: CreateFamilyShareCodeViewModel

    init(familyId: String, existingShareCode: ShareCode? = nil) {
        self.familyId = familyId
        self.existingShareCode = existingShareCode
        _viewModel = StateObject(
            wrappedValue: CreateFamilyShareCodeViewModel(
                familyId: familyId,
                existingShareCode: existingShareCode
            )
        )
    }

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

                                HStack {
                                    Text(code)
                                        .font(.system(.largeTitle, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .accessibilityLabel("share_code.a11y.code".localized(code))

                                    Button {
                                        viewModel.copyShareCode(code)
                                    } label: {
                                        Image(systemName: viewModel.copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                            .font(.title2)
                                    }
                                    .accessibleButton(
                                        label: viewModel.copiedToClipboard
                                            ? "share_code.a11y.copied".localized
                                            : "share_code.a11y.copy".localized,
                                        hint: "share_code.a11y.copy_hint".localized
                                    )
                                }
                                .padding()
                                .background(Color.Theme.cardBackground)
                                .cornerRadius(12)

                                if viewModel.copiedToClipboard {
                                    Text("Copied to clipboard".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .transition(.opacity)
                                        .accessibilityHidden(true)
                                }

                                if let expiresAt = viewModel.expiresAt {
                                    let expirationText = viewModel.timeUntilExpiration(expiresAt)
                                    if expirationText == "Expired".localized {
                                        Text("Refresh Share Code".localized)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                    } else {
                                        Text("Expires in %@".localized(expirationText))
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                }

                                Button {
                                    viewModel.refreshShareCode()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                            .accessibleDecorative()
                                        Text("Refresh Share Code".localized)
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isGenerating || !authService.isOnline)
                                .accessibleButton(label: "share_code.a11y.refresh".localized)
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
                                        .accessibilityLabel("share_code.a11y.qr".localized(code))

                                    Button {
                                        viewModel.showShareSheet = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                                .accessibleDecorative()
                                            Text("Share QR Code".localized)
                                        }
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibleButton(
                                        label: "share_code.a11y.share_qr".localized,
                                        hint: "share_code.a11y.share_qr_hint".localized
                                    )
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

                                Text("Share this code or QR code with someone you want to invite to your family. They can enter it in the Family section to request to join.".localized)
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
                        Text("Generate a share code to invite family members".localized)
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
                        .accessibleButton(label: "share_code.a11y.generate".localized)
                    }
                    .padding()
                }
            }
            .navigationTitle("Share Code".localized)
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
                viewModel.onAppear()
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                viewModel.tickClock()
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let qrImage = viewModel.qrCodeImage {
                    ShareSheet(activityItems: [qrImage])
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    CreateFamilyShareCodeSheet(familyId: "test")
        .environmentObject(FirebaseAuthService())
}
