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
    @StateObject private var tripLimitPaywallViewModel = PaywallViewModel()
    /// COPPA F-7 (FR-34) rendered projection.
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared

    init() {
        let tripRepo = TripInviteRepository.shared
        _viewModel = StateObject(wrappedValue: PendingTripsViewModel(
            tripInviteRepository: tripRepo,
            authService: FirebaseAuthService()
        ))
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if viewModel.isLoading {
                    ProgressView()
                        .accessibilityLabel("Loading".localized)
                } else if viewModel.incomingInvites.isEmpty && viewModel.outgoingInvites.isEmpty {
                    emptyState
                } else {
                    List {
                        if !viewModel.incomingInvites.isEmpty {
                            Section("Incoming Invites".localized) {
                                ForEach(viewModel.incomingInvites, id: \.inviteId) { invite in
                                    TripInviteRow(
                                        invite: invite,
                                        snapshot: viewModel.displaySnapshot(for: invite, isIncoming: true),
                                        isIncoming: true,
                                        isAcceptBusy: viewModel.isBusy(inviteId: invite.inviteId, kind: .accept),
                                        isDeclineBusy: viewModel.isBusy(inviteId: invite.inviteId, kind: .decline),
                                        isCancelBusy: false,
                                        isDisabled: viewModel.isInviteDisabled(invite.inviteId),
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
                                        snapshot: viewModel.displaySnapshot(for: invite, isIncoming: false),
                                        isIncoming: false,
                                        isAcceptBusy: false,
                                        isDeclineBusy: false,
                                        isCancelBusy: viewModel.isBusy(inviteId: invite.inviteId, kind: .cancel),
                                        isDisabled: viewModel.isInviteDisabled(invite.inviteId),
                                        onAccept: nil,
                                        onDecline: nil,
                                        onCancel: invite.statusEnum == .sent || invite.statusEnum == .pending
                                            ? { viewModel.cancel(invite: invite) }
                                            : nil
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
            .onAppear {
                TripInviteRepository.shared.setModelContext(modelContext)
                viewModel.setAuthService(authService)
                viewModel.onAppear()
                AnalyticsService.shared.logScreenView(screenName: "pending_trips")
            }
            .sheet(isPresented: Binding(
                get: { viewModel.shouldPresentTripLimitPaywall },
                set: { if !$0 { viewModel.dismissTripLimitPaywall() } }
            )) {
                // COPPA F-7 (FR-34): child sessions get the informational variant in
                // the same slot — never pricing/purchase UI.
                switch ChildPremiumSheetVariant.variant(purchasesSuppressed: childPostures.arePurchasesSuppressed) {
                case .childInfo:
                    ChildPremiumInfoView(context: .tripLimit, onDismiss: { viewModel.dismissTripLimitPaywall() })
                case .paywall:
                    PaywallView(
                        viewModel: tripLimitPaywallViewModel,
                        onDismiss: { viewModel.dismissTripLimitPaywall() },
                        source: TripLimitGateSource.inviteAccept.rawValue
                    )
                    .onAppear {
                        tripLimitPaywallViewModel.setTripLimitContext()
                    }
                }
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
    let snapshot: InviteDisplaySnapshot
    let isIncoming: Bool
    let isAcceptBusy: Bool
    let isDeclineBusy: Bool
    let isCancelBusy: Bool
    let isDisabled: Bool
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
                    Text(snapshot.counterpartyLine)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    if let games = snapshot.gamesOnTripLine {
                        Text(games)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Text(snapshot.statusLine)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if isIncoming, invite.statusEnum == .pending {
                HStack(spacing: 12) {
                    Button {
                        onAccept?()
                    } label: {
                        InviteActionLabel(
                            title: "Accept".localized,
                            isBusy: isAcceptBusy,
                            busyKind: .accept
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Theme.primaryBlue)
                    .disabled(isDisabled)
                    .accessibleButton(
                        label: isAcceptBusy
                            ? InviteBusyKind.accept.localizedBusyTitle
                            : "Accept invite".localized,
                        hint: "Accepts this trip invite".localized
                    )

                    Button {
                        onDecline?()
                    } label: {
                        InviteActionLabel(
                            title: "Decline".localized,
                            isBusy: isDeclineBusy,
                            busyKind: .decline
                        )
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(isDisabled)
                    .accessibleButton(
                        label: isDeclineBusy
                            ? InviteBusyKind.decline.localizedBusyTitle
                            : "Decline invite".localized,
                        hint: "Declines this trip invite".localized
                    )
                }
            } else if !isIncoming, let onCancel = onCancel {
                Button {
                    onCancel()
                } label: {
                    InviteActionLabel(
                        title: "Cancel Invite".localized,
                        isBusy: isCancelBusy,
                        busyKind: .cancel
                    )
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .disabled(isDisabled)
                .accessibleButton(
                    label: isCancelBusy
                        ? InviteBusyKind.cancel.localizedBusyTitle
                        : "Cancel invite".localized,
                    hint: "Cancels this outgoing invite".localized
                )
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
