//
//  CreateFamilyShareCodeSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct CreateFamilyShareCodeSheet: View {
    let familyId: String
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
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
                                
                                Text(code)
                                    .font(.system(.largeTitle, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .padding()
                                    .background(Color.Theme.cardBackground)
                                    .cornerRadius(12)
                                
                                if let expiresAt = expiresAt {
                                    Text("Expires in \(timeUntilExpiration(expiresAt))".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
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
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                if shareCode == nil {
                    generateCode()
                }
            }
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
    
    private func timeUntilExpiration(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        let minutes = Int(timeInterval / 60)
        return "\(minutes) minutes".localized
    }
}

#Preview {
    CreateFamilyShareCodeSheet(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

