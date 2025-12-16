//
//  FamilyInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI

struct FamilyInviteDetail: View {
    let inviteId: String
    let familyId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var isProcessing = false
    @State private var hasAccepted = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Family Invitation".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    if hasAccepted {
                        VStack(spacing: 12) {
                            Text("Waiting for Captain approval".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            
                            Text("A family captain will review your request".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                        }
                        .padding()
                    } else {
                        Button {
                            respondToInvite(accept: true)
                        } label: {
                            Text("Accept".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                        
                        Button {
                            respondToInvite(accept: false)
                        } label: {
                            Text("Decline".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                    }
                    
                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding()
            }
            .navigationTitle("Family Invite".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func respondToInvite(accept: Bool) {
        isProcessing = true
        
        Task {
            // TODO: Call Cloud Function
            await MainActor.run {
                isProcessing = false
                if accept {
                    hasAccepted = true
                    AnalyticsService.shared.log(.familyInviteUserAccepted)
                } else {
                    AnalyticsService.shared.log(.familyInviteUserDeclined)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    FamilyInviteDetail(inviteId: "test", familyId: "test")
        .environmentObject(FirebaseAuthService())
}

