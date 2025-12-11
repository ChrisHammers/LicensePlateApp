//
//  FriendRequestManagementView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct FriendRequestManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \FriendRequest.createdAt, order: .reverse) private var allRequests: [FriendRequest]
    
    var pendingRequests: [FriendRequest] {
        allRequests.filter { $0.status == .pending || $0.status == .requiresCaptainApproval }
    }
    
    @State private var selectedRequest: FriendRequest?
    @State private var showApproveConfirmation = false
    @State private var showDenyConfirmation = false
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var scoutRequests: [FriendRequest] {
        // Filter requests that need Captain approval (requests to Scouts)
        pendingRequests.filter { $0.status == .requiresCaptainApproval }
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if scoutRequests.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        
                        Text("No Pending Approvals".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("All friend requests to Scouts have been handled.".localized)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        Section("Pending Approvals".localized) {
                            ForEach(scoutRequests) { request in
                                FriendRequestRow(request: request) {
                                    selectedRequest = request
                                    showApproveConfirmation = true
                                } onDeny: {
                                    selectedRequest = request
                                    showDenyConfirmation = true
                                }
                            }
                        }
                        .textCase(nil)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Friend Request Approvals".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Approve Friend Request".localized, isPresented: $showApproveConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Approve".localized) {
                    if let request = selectedRequest {
                        approveRequest(request)
                    }
                }
            } message: {
                if let request = selectedRequest {
                    let userName = UserLookupHelper.getUserName(for: request.fromUserID, in: modelContext) ?? "Unknown User".localized
                    Text("Approve friend request from \(userName)?".localized)
                }
            }
            .alert("Deny Friend Request".localized, isPresented: $showDenyConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Deny".localized, role: .destructive) {
                    if let request = selectedRequest {
                        denyRequest(request)
                    }
                }
            } message: {
                if let request = selectedRequest {
                    let userName = UserLookupHelper.getUserName(for: request.fromUserID, in: modelContext) ?? "Unknown User".localized
                    Text("Deny friend request from \(userName)?".localized)
                }
            }
        }
    }
    
    private func approveRequest(_ request: FriendRequest) {
        request.approve(by: currentUser?.id)
        
        // Add to friend lists
        let fromUserID = request.fromUserID
        let toUserID = request.toUserID
        
        if let fromUser = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == fromUserID
        })).first,
           let toUser = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == toUserID
        })).first {
            if !fromUser.friendIDs.contains(toUserID) {
                fromUser.friendIDs.append(toUserID)
                fromUser.needsSync = true
            }
            if !toUser.friendIDs.contains(fromUserID) {
                toUser.friendIDs.append(fromUserID)
                toUser.needsSync = true
            }
            
            // Sync to Firebase
            Task {
                do {
                    try await FirebaseFamilySyncService.shared.saveFriendRequestToFirestore(request)
                    try await authService.saveUserDataToFirestore(fromUser)
                    try await authService.saveUserDataToFirestore(toUser)
                } catch {
                    print("Error syncing friend request approval: \(error)")
                }
            }
        }
        
        selectedRequest = nil
    }
    
    private func denyRequest(_ request: FriendRequest) {
        request.deny()
        selectedRequest = nil
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onApprove: () -> Void
    let onDeny: () -> Void
    @Environment(\.modelContext) private var modelContext
    
    private var userName: String {
        UserLookupHelper.getUserName(for: request.fromUserID, in: modelContext) ?? "Unknown User".localized
    }
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.headline)
                
                Text("Wants to be friends with a Scout".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(request.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    onApprove()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
                .accessibilityLabel("Approve".localized)
                
                Button {
                    onDeny()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
                .accessibilityLabel("Deny".localized)
            }
        }
        .padding(.vertical, 4)
    }
}

