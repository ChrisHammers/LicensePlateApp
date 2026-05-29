//
//  TripParticipantsView.swift
//  LicensePlateApp
//
//  Step 11.5 — Passenger List for a trip session.
//

import SwiftUI

struct TripParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FirebaseAuthService
    @StateObject private var viewModel: TripParticipantsViewModel
    @State private var isShowingInviteSheet = false

    init(sessionId: UUID) {
        _viewModel = StateObject(wrappedValue: TripParticipantsViewModel(sessionId: sessionId))
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                            .listRowBackground(Color.Theme.cardBackground)
                    }

                    Section("Passengers".localized) {
                        ForEach(viewModel.passengers) { passenger in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(passenger.displayName)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    Text(passenger.roleLabel)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                                Spacer()
                                if passenger.isCreator {
                                    Text("Creator".localized)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.Theme.cardBackground)

                    Section("Pending Invites".localized) {
                        if viewModel.pendingInviteRows.isEmpty {
                            Text("No pending invites".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        } else {
                            ForEach(viewModel.pendingInviteRows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.inviteeDisplayName)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    Text(row.statusLabel)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(row.inviteeDisplayName), \(row.statusLabel)")
                            }
                        }
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Passenger List".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite Players".localized) {
                        isShowingInviteSheet = true
                    }
                }
            }
            .sheet(isPresented: $isShowingInviteSheet) {
                InvitePlayersView(
                    viewModel: InvitePlayersViewModel(
                        mode: .sendInvites,
                        tripSessionId: viewModel.sessionId,
                        tripName: viewModel.tripName,
                        authService: authService
                    ),
                    title: "Invite Players".localized
                ) { _ in
                    Task { await viewModel.reload() }
                }
                .environmentObject(authService)
            }
            .onAppear {
                viewModel.onAppear()
            }
        }
    }
}

#Preview("Passenger List") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return TripParticipantsView(sessionId: UUID())
        .environmentObject(auth)
}
