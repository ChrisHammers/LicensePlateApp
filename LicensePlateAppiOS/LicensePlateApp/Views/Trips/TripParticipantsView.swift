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

    init(sessionId: UUID, authService: FirebaseAuthService) {
        _viewModel = StateObject(wrappedValue: TripParticipantsViewModel(
            sessionId: sessionId,
            authService: authService
        ))
    }

    /// Preview / tests
    init(viewModel: TripParticipantsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    Section("Driver & Passengers".localized) {
                        ForEach(viewModel.passengers) { passenger in
                            PassengerListRow(
                                passenger: passenger,
                                canRemove: viewModel.canRemove(passengerUserId: passenger.userId),
                                isRemoving: viewModel.isRemovingPassenger,
                                onRemove: {
                                    viewModel.confirmRemovePassenger(userId: passenger.userId)
                                }
                            )
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
            .navigationTitle("Driver & Passengers".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
                if viewModel.canInvitePassengers {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Invite Passengers".localized) {
                            isShowingInviteSheet = true
                        }
                    }
                }
            }
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Remove Passenger".localized,
                isPresented: Binding(
                    get: { viewModel.passengerIdPendingRemoval != nil },
                    set: { if !$0 { viewModel.cancelRemovePassenger() } }
                )
            ) {
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelRemovePassenger()
                }
                Button("Remove".localized, role: .destructive) {
                    viewModel.removePendingPassenger()
                }
            } message: {
                Text("They will leave this trip and need a new invite to rejoin.".localized)
            }
            .sheet(isPresented: $isShowingInviteSheet) {
                InvitePlayersView(
                    viewModel: InvitePlayersViewModel(
                        mode: .sendInvites,
                        tripSessionId: viewModel.sessionId,
                        tripName: viewModel.tripName,
                        authService: authService
                    ),
                    title: "Invite Passengers".localized
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

private struct PassengerListRow: View {
    let passenger: PassengerDisplayRow
    var canRemove: Bool = false
    var isRemoving: Bool = false
    var onRemove: (() -> Void)? = nil
    @EnvironmentObject private var authService: FirebaseAuthService
    @State private var user: AppUser?

    private var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    private var decoratedDisplayName: String {
        let raw = user?.displayName ?? passenger.displayName
        return ParticipantDisplayName.decorated(
            raw,
            userId: passenger.userId,
            currentUserId: currentUserId
        )
    }

    var body: some View {
        Group {
            if let user {
                UserDetailNavigationLink(
                    user: user,
                    isSelfProfile: UserDetailNavigation.isSelfProfile(
                        user: user,
                        currentUserId: currentUserId
                    )
                ) {
                    passengerRowContent
                }
            } else {
                passengerRowContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .task {
            await loadUser()
        }
    }

    private var passengerRowContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(decoratedDisplayName)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(passenger.roleLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            Spacer()
            if passenger.isCreator {
                Text("Driver".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.green)
            }
            if canRemove {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Text("Remove".localized)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                }
                .disabled(isRemoving)
                .accessibleButton(
                    label: "trip.a11y.remove_passenger".localized(decoratedDisplayName),
                    hint: "trip.a11y.remove_passenger_hint".localized
                )
            }
        }
    }

    private var accessibilityLabelText: String {
        var parts = [decoratedDisplayName, passenger.roleLabel]
        if passenger.isCreator {
            parts.append("Driver".localized)
        }
        return parts.joined(separator: ", ")
    }

    private func loadUser() async {
        do {
            user = try await UserRepository.shared.getUser(userId: passenger.userId)
        } catch {
            user = nil
        }
    }
}

#Preview("Driver & Passengers — driver") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return TripParticipantsView(sessionId: UUID(), authService: auth)
        .environmentObject(auth)
}

#Preview("Driver & Passengers — passenger") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "passenger", userName: "Passenger", firebaseUID: "passenger")
    return TripParticipantsView(sessionId: UUID(), authService: auth)
        .environmentObject(auth)
}
