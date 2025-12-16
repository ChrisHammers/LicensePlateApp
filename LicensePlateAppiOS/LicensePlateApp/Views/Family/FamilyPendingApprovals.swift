//
//  FamilyPendingApprovals.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilyPendingApprovals: View {
    let familyId: String
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var familyRepository = FamilyRepository()
    @State private var pendingRequests: [PendingJoinRequest] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    if pendingRequests.isEmpty {
                        Text("No pending requests".localized)
                            .foregroundStyle(Color.Theme.softBrown)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(pendingRequests) { request in
                            PendingApprovalRow(request: request, familyId: familyId)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Pending Approvals".localized)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                familyRepository.setModelContext(modelContext)
                pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
            }
        }
    }
}

struct PendingApprovalRow: View {
    let request: PendingJoinRequest
    let familyId: String
    @State private var isProcessing = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text(request.user?.displayName ?? "User")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Approve".localized) {
                    approveRequest()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Theme.primaryBlue)
                .disabled(isProcessing)
                
                Button("Decline".localized) {
                    declineRequest()
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func approveRequest() {
        isProcessing = true
        // TODO: Call Cloud Function
        AnalyticsService.shared.log(.familyJoinRequestApproved)
    }
    
    private func declineRequest() {
        isProcessing = true
        // TODO: Call Cloud Function
        AnalyticsService.shared.log(.familyJoinRequestDeclined)
    }
}

#Preview {
    FamilyPendingApprovals(familyId: "test")
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [PendingJoinRequest.self], inMemory: true)
}

