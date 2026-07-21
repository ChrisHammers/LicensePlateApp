//
//  FamilyPendingApprovals.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData
import Combine

struct FamilyPendingApprovals: View {
    let familyId: String
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    @State private var pendingRequests: [PendingJoinRequest] = []
    @State private var pendingObservation: AnyCancellable?
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if pendingRequests.isEmpty {
                        Text("No pending requests".localized)
                            .foregroundStyle(Color.Theme.softBrown)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .listRowBackground(Color.Theme.cardBackground)
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
                            .listRowBackground(Color.Theme.cardBackground)
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
                UserRepository.shared.setModelContext(modelContext)
                loadPendingRequests()
                startObservingPendingRequests()
            }
            .task(id: familyId) {
                familyRepository.setModelContext(modelContext)
                UserRepository.shared.setModelContext(modelContext)
                await refreshPendingRequests()
            }
            .onDisappear {
                pendingObservation?.cancel()
                pendingObservation = nil
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
    
    private func startObservingPendingRequests() {
        pendingObservation?.cancel()
        pendingObservation = familyRepository.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { pendingByFamily in
                guard pendingByFamily[familyId] != nil else { return }
                loadPendingRequests()
            }
    }
    
    private func refreshPendingRequests() async {
        do {
            let linked = try await familyRepository.fetchPendingRequests(familyId: familyId)
            await MainActor.run {
                pendingRequests = linked.filter { $0.statusEnum == .pending }
            }
        } catch {
            // Error fetching - use cached data
            await MainActor.run {
                loadPendingRequests()
            }
        }
    }
}

struct PendingApprovalRow: View {
    let request: PendingJoinRequest
    let familyId: String
    let onRequestProcessed: () -> Void
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var resolvedUser: AppUser?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var hasProcessed = false

    private var displayUser: AppUser? {
        request.user ?? resolvedUser
    }
    
    var body: some View {
        HStack {
            if let user = displayUser {
                UserIdentityRowView(user: user, subtitle: nil, avatarSize: 50)
            } else {
                HStack(spacing: 12) {
                    AvatarImageView(avatarId: nil, size: 50)

                    Text("User".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)

                }
            }
            
            HStack(spacing: 12) {
                Button {
                    Task { await approveRequest() }
                } label: {
                    Text("Approve".localized)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Theme.primaryBlue)
                .disabled(isProcessing || hasProcessed)
                .accessibleButton(label: "family.a11y.approve_join".localized)

                Button {
                    Task { await declineRequest() }
                } label: {
                    Text("Decline".localized)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || hasProcessed)
                .accessibleButton(label: "family.a11y.decline_join".localized)
            }
            .layoutPriority(1)
            
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pendingApprovalAccessibilityLabel)
        .task(id: request.userId) {
            await resolveUserIfNeeded()
        }
        .alert("Error".localized, isPresented: $showError) {
            Button("OK".localized, role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error".localized)
        }
    }

    private var pendingApprovalAccessibilityLabel: String {
        if let user = displayUser {
            return "\(user.displayName), @\(user.userName)"
        }
        return "User".localized
    }

    private func resolveUserIfNeeded() async {
        if request.user != nil {
            await MainActor.run { resolvedUser = nil }
            return
        }
        do {
            if let fetched = try await UserRepository.shared.getUser(userId: request.userId) {
                await MainActor.run {
                    self.resolvedUser = fetched
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ PendingApprovalRow failed to resolve user \(request.userId): \(error.localizedDescription)")
            #endif
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
