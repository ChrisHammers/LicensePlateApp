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
    private let familyRepository = FamilyRepository.shared
    @State private var pendingRequests: [PendingJoinRequest] = []
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if pendingRequests.isEmpty {
                        Text("No pending requests".localized)
                            .foregroundStyle(Color.Theme.softBrown)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(pendingRequests) { request in
                            PendingApprovalRow(
                                request: request,
                                familyId: familyId,
                                onRequestProcessed: {
                                    // Refresh list after approval/decline
                                    Task {
                                        await refreshPendingRequests()
                                    }
                                }
                            )
                            .environmentObject(authService)
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
                loadPendingRequests()
            }
            .refreshable {
                await refreshPendingRequests()
            }
        }
    }
    
    private func loadPendingRequests() {
        pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
            .filter { $0.statusEnum == .pending }
    }
    
    private func refreshPendingRequests() async {
        do {
            _ = try await familyRepository.fetchPendingRequests(familyId: familyId)
            await MainActor.run {
                loadPendingRequests()
            }
        } catch {
            // Error fetching - use cached data
        }
    }
}

struct PendingApprovalRow: View {
    let request: PendingJoinRequest
    let familyId: String
    let onRequestProcessed: () -> Void
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var hasProcessed = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.user?.displayName ?? "User")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                if let userName = request.user?.userName {
                    Text("@\(userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Approve".localized) {
                    Task {
                        await approveRequest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Theme.primaryBlue)
                .disabled(isProcessing || hasProcessed)
                
                Button("Decline".localized) {
                    Task {
                        await declineRequest()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || hasProcessed)
            }
        }
        .padding(.vertical, 8)
        .alert("Error".localized, isPresented: $showError) {
            Button("OK".localized, role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error".localized)
        }
    }
    
    private func approveRequest() async {
        // Prevent duplicate calls
        guard !isProcessing && !hasProcessed else { return }
        
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        do {
            try await FamilyRepository.shared.respondToPendingRequest(
                familyId: familyId,
                requestId: request.requestId,
                approve: true
            )
            AnalyticsService.shared.log(.familyJoinRequestApproved)
            
            await MainActor.run {
                hasProcessed = true
                isProcessing = false
            }
            
            // Notify parent to refresh list
            onRequestProcessed()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isProcessing = false
            }
        }
    }
    
    private func declineRequest() async {
        // Prevent duplicate calls
        guard !isProcessing && !hasProcessed else { return }
        
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        do {
            try await FamilyRepository.shared.respondToPendingRequest(
                familyId: familyId,
                requestId: request.requestId,
                approve: false
            )
            AnalyticsService.shared.log(.familyJoinRequestDeclined)
            
            await MainActor.run {
                hasProcessed = true
                isProcessing = false
            }
            
            // Notify parent to refresh list
            onRequestProcessed()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isProcessing = false
            }
        }
    }
}

#Preview {
    FamilyPendingApprovals(familyId: "test")
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [PendingJoinRequest.self], inMemory: true)
}

