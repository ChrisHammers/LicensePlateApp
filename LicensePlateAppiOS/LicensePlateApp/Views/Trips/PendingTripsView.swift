//
//  PendingTripsView.swift
//  LicensePlateApp
//
//  Step 04 — Pending trip invites: incoming (Accept/Decline) and outgoing (Cancel).
//  Not linked from main list; reserved for future "See all" or deep links.
//

import SwiftUI
import SwiftData

struct PendingTripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: PendingTripsViewModel

    init() {
        let tripRepo = TripInviteRepository.shared
        _viewModel = StateObject(wrappedValue: PendingTripsViewModel(
            tripInviteRepository: tripRepo,
            authService: FirebaseAuthService()
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.incomingInvites.isEmpty && viewModel.outgoingInvites.isEmpty {
                    emptyState
                } else {
                    List {
                        if let error = viewModel.errorMessage {
                            Section {
                                Text(error)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.red)
                            }
                        }
                        if !viewModel.incomingInvites.isEmpty {
                            Section("Incoming Invites".localized) {
                                ForEach(viewModel.incomingInvites, id: \.inviteId) { invite in
                                    TripInviteRow(
                                        invite: invite,
                                        isIncoming: true,
                                        onAccept: { viewModel.accept(invite: invite) },
                                        onDecline: { viewModel.decline(invite: invite) },
                                        onCancel: nil
                                    )
                                }
                            }
                            .textCase(nil)
                        }
                        if !viewModel.outgoingInvites.isEmpty {
                            Section("Outgoing Invites".localized) {
                                ForEach(viewModel.outgoingInvites, id: \.inviteId) { invite in
                                    TripInviteRow(
                                        invite: invite,
                                        isIncoming: false,
                                        onAccept: nil,
                                        onDecline: nil,
                                        onCancel: invite.statusEnum == .sent || invite.statusEnum == .pending ? { viewModel.cancel(invite: invite) } : nil
                                    )
                                }
                            }
                            .textCase(nil)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Pending Trips".localized)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("pendingTrips_screen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        FeedbackService.shared.buttonTap()
                        dismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Close".localized)
                    .accessibilityHint("Closes the Pending Trips screen".localized)
                    .accessibilityIdentifier("pendingTrips_closeButton")
                }
            }
            .onAppear {
                TripInviteRepository.shared.setModelContext(modelContext)
                viewModel.setAuthService(authService)
                viewModel.onAppear()
                AnalyticsService.shared.logScreenView(screenName: "pending_trips")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending trip invites".localized)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 60))
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                .accessibilityHidden(true)

            Text("No pending trip invites".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("When someone invites you to a trip, or you invite others, they will appear here.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pending trip invites. When someone invites you to a trip, or you invite others, they will appear here.".localized)
        .accessibilityIdentifier("pendingTrips_emptyState")
    }
}

// MARK: - Row

private struct TripInviteRow: View {
    let invite: TripInvite
    let isIncoming: Bool
    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invite.tripName)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("Inviter: %@".localized(invite.fromUserId))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text("Mode: %@".localized(invite.tripMode))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text("Status: %@".localized(invite.statusEnum.rawValue))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if isIncoming, invite.statusEnum == .pending {
                HStack(spacing: 12) {
                    Button("Accept".localized) {
                        onAccept?()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Theme.primaryBlue)
                    .accessibilityLabel("Accept invite".localized)
                    .accessibilityHint("Accepts this trip invite".localized)

                    Button("Decline".localized) {
                        onDecline?()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Decline invite".localized)
                    .accessibilityHint("Declines this trip invite".localized)
                }
            } else if !isIncoming, let onCancel = onCancel {
                Button("Cancel Invite".localized) {
                    onCancel()
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("Cancel invite".localized)
                .accessibilityHint("Cancels this outgoing invite".localized)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch invite.statusEnum {
        case .pending, .sent: return Color.Theme.accentYellow
        case .accepted: return .green
        case .declined, .canceled, .expired: return Color.Theme.softBrown
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    PendingTripsView()
    .environmentObject(FirebaseAuthService())
    .modelContainer(for: TripInvite.self, inMemory: true)
}

#Preview("With mock invites") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TripInvite.self, configurations: config)
    let ctx = ModelContext(container)
    let params = PreviewInviteFixturesParams.pendingInvite()
    let invite1 = TripInvite(
        inviteId: params.inviteId,
        tripSessionId: params.tripSessionId,
        tripName: params.tripName,
        tripMode: params.tripMode,
        fromUserId: params.fromUserId,
        toUserId: params.toUserId,
        status: params.status,
        createdAt: params.createdAt,
        expiresAt: params.expiresAt,
        respondedAt: params.respondedAt
    )
    ctx.insert(invite1)
    try? ctx.save()

    return PendingTripsView()
        .environmentObject(FirebaseAuthService())
        .modelContainer(container)
}
