//
//  CreateFamilyShareCodeSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData
import Combine
import UIKit

struct CreateFamilyShareCodeSheet: View {
    let familyId: String
    let existingShareCode: ShareCode? // Optional existing share code to display
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    @State private var shareCode: String?
    @State private var expiresAt: Date?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var qrCodeImage: UIImage?
    @State private var currentTime = Date()
    @State private var currentShareCodeId: String? // Track the current share code ID for revocation
    @State private var showShareSheet = false
    @State private var copiedToClipboard = false
    
    init(familyId: String, existingShareCode: ShareCode? = nil) {
        self.familyId = familyId
        self.existingShareCode = existingShareCode
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if isGenerating {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let code = shareCode {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Share Code Display
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
                                        copyShareCode(code)
                                    } label: {
                                        Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                            .font(.title2)
                                    }
                                    .accessibleButton(
                                        label: copiedToClipboard
                                            ? "share_code.a11y.copied".localized
                                            : "share_code.a11y.copy".localized,
                                        hint: "share_code.a11y.copy_hint".localized
                                    )
                                }
                                .padding()
                                .background(Color.Theme.cardBackground)
                                .cornerRadius(12)
                                
                                if copiedToClipboard {
                                    Text("Copied to clipboard".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .transition(.opacity)
                                        .accessibilityHidden(true)
                                }
                                
                                if let expiresAt = expiresAt {
                                    let expirationText = timeUntilExpiration(expiresAt, currentTime: currentTime)
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
                                
                                // Refresh Share Code Button
                                Button {
                                    refreshShareCode()
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
                                .disabled(isGenerating || !authService.isOnline)
                                .accessibleButton(label: "share_code.a11y.refresh".localized)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.Theme.cardBackground)
                            .cornerRadius(16)
                            
                            // QR Code Display
                            if let qrImage = qrCodeImage {
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
                                        showShareSheet = true
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
                            
                            // Instructions
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
                            generateCode()
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
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                currentTime = Date()
                
                // If existing share code provided, display it
                if let existing = existingShareCode, !existing.isExpired {
                    shareCode = existing.code
                    expiresAt = existing.expiresAt
                    currentShareCodeId = existing.codeId
                    // Generate QR code for existing code
                    qrCodeImage = QRCodeService.shared.generateQRCode(from: existing.code)
                } else if shareCode == nil {
                    // Only generate new code if no existing code provided
                    generateCode()
                }
                
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                currentTime = Date()
                // Timer updates the expiration display, but doesn't clear the code
                // User can refresh to get a new code
            }
            .sheet(isPresented: $showShareSheet) {
                if let qrImage = qrCodeImage {
                    ShareSheet(activityItems: [qrImage])
                }
            }
        }
    }
    
    private func copyShareCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedToClipboard = true
        UIAccessibility.post(notification: .announcement, argument: "share_code.a11y.copied".localized)
        
        // Reset the checkmark after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
    
    private func generateCode() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await familyRepository.createShareCode(type: "family", familyId: familyId)
                
                // Generate QR code
                let qrString = result.code
                let qrImage = QRCodeService.shared.generateQRCode(from: qrString)
                
                await MainActor.run {
                    shareCode = result.code
                    expiresAt = result.expiresAt
                    currentShareCodeId = result.codeId
                    qrCodeImage = qrImage
                    isGenerating = false
                    AnalyticsService.shared.log(.shareCodeGenerated(type: "family"))
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                    print("❌ Family share code generation error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func refreshShareCode() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                // First, revoke the current share code if it exists
                if let codeId = currentShareCodeId {
                    try? await familyRepository.revokeShareCode(codeId: codeId)
                }
                
                // Then create a new share code
                let result = try await familyRepository.createShareCode(type: "family", familyId: familyId)
                
                // Generate QR code
                let qrString = result.code
                let qrImage = QRCodeService.shared.generateQRCode(from: qrString)
                
                await MainActor.run {
                    shareCode = result.code
                    expiresAt = result.expiresAt
                    currentShareCodeId = result.codeId
                    qrCodeImage = qrImage
                    isGenerating = false
                    currentTime = Date() // Reset timer
                    AnalyticsService.shared.log(.shareCodeGenerated(type: "family"))
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                    print("❌ Family share code refresh error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func timeUntilExpiration(_ date: Date, currentTime: Date) -> String {
        let timeInterval = date.timeIntervalSince(currentTime)
        guard timeInterval > 0 else {
            return "Expired".localized
        }
        let minutes = Int(timeInterval / 60)
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "share_code.minutes".localized(minutes)
        } else {
            return "share_code.seconds".localized(seconds)
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    CreateFamilyShareCodeSheet(familyId: "test", existingShareCode: nil)
        .environmentObject(FirebaseAuthService())
}

