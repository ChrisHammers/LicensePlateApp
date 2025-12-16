//
//  FriendRequestDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI

struct FriendRequestDetail: View {
    let friendship: Friendship
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // User info
                    Circle()
                        .fill(Color.Theme.primaryBlue.opacity(0.3))
                        .frame(width: 100, height: 100)
                    
                    Text("Friend Request".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Wants to be your friend".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Spacer()
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            respondToRequest(accept: true)
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
                            respondToRequest(accept: false)
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
                    .padding()
                    
                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding()
            }
            .navigationTitle("Friend Request".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error".localized, isPresented: .constant(errorMessage != nil)) {
                Button("OK".localized) {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func respondToRequest(accept: Bool) {
        isProcessing = true
        
        // Call Cloud Function to respond
        Task {
            // TODO: Implement Cloud Function call
            await MainActor.run {
                isProcessing = false
                if accept {
                    AnalyticsService.shared.log(.friendRequestAccepted)
                } else {
                    AnalyticsService.shared.log(.friendRequestDeclined)
                }
                dismiss()
            }
        }
    }
}

#Preview {
    FriendRequestDetail(friendship: Friendship(
        friendshipId: "test",
        userA: "user1",
        userB: "user2",
        status: .pending,
        initiatedBy: "user1"
    ))
    .environmentObject(FirebaseAuthService())
}

