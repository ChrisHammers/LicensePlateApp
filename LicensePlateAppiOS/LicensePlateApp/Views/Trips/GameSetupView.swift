//
//  GameSetupView.swift
//  LicensePlateApp
//
//  Game type, play style, and country scope for new-trip and add-game flows.
//

import SwiftUI
import SwiftData

struct GameSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameSetupViewModel
    @StateObject private var tripLimitPaywallViewModel = PaywallViewModel()
    /// COPPA F-7 (FR-34) rendered projection.
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared
    @State private var pendingCreatedSession: TripSession?

    var onCreated: ((TripSession) -> Void)?
    var onAdded: (() -> Void)?

    init(
        viewModel: GameSetupViewModel,
        onCreated: ((TripSession) -> Void)? = nil,
        onAdded: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onCreated = onCreated
        self.onAdded = onAdded
    }

    private var defaultGameModeBinding: Binding<GameMode> {
        Binding(
            get: { viewModel.defaultGameMode },
            set: { viewModel.defaultGameMode = $0 }
        )
    }

    private var isEmbeddedInFlow: Bool {
        if case .newTrip = viewModel.context { return onCreated != nil }
        return false
    }

    var body: some View {
        AppBackgroundView {
            List {
                gamesSection
                gameOptionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Game Setup".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.logSetupScreenAppeared()
        }
        .toolbar {
            if !isEmbeddedInFlow {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        FeedbackService.shared.buttonTap()
                        dismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(viewModel.isSubmitting)
                    .accessibilityLabel("Cancel".localized)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    primaryActionTapped()
                } label: {
                    InviteActionLabel(
                        title: viewModel.primaryActionTitle,
                        isBusy: viewModel.isSubmitting,
                        busyTitle: viewModel.primaryActionTitle
                    )
                }
                .fontWeight(.semibold)
                .foregroundStyle(!viewModel.canConfirm || viewModel.isSubmitting ? .secondary : Color.Theme.primaryBlue)
                .disabled(!viewModel.canConfirm || viewModel.isSubmitting)
                .accessibilityLabel(viewModel.primaryActionTitle)
                .accessibilityHint(primaryActionAccessibilityHint)
            }
        }
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK".localized) { viewModel.clearError() }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert("Some invites failed".localized, isPresented: $viewModel.showInvitePartialFailureAlert) {
            Button("OK".localized) {
                viewModel.dismissInvitePartialFailureAlert()
                if let session = pendingCreatedSession {
                    finishCreatedTrip(session)
                }
            }
        } message: {
            Text("Some trip invites could not be sent. Your trip was created successfully.".localized)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.shouldPresentTripLimitPaywall },
            set: { if !$0 { viewModel.dismissTripLimitPaywall() } }
        )) {
            // COPPA F-7 (FR-34): child sessions get the informational variant in the
            // same slot — never pricing/purchase UI.
            switch ChildPremiumSheetVariant.variant(purchasesSuppressed: childPostures.arePurchasesSuppressed) {
            case .childInfo:
                ChildPremiumInfoView(context: .tripLimit, onDismiss: { viewModel.dismissTripLimitPaywall() })
            case .paywall:
                PaywallView(
                    viewModel: tripLimitPaywallViewModel,
                    onDismiss: { viewModel.dismissTripLimitPaywall() },
                    source: TripLimitGateSource.create.rawValue
                )
                .onAppear {
                    tripLimitPaywallViewModel.setTripLimitContext()
                }
            }
        }
    }

    private var primaryActionAccessibilityHint: String {
        if !viewModel.canConfirm {
            return "Select at least one game and one country before continuing".localized
        }
        switch viewModel.context {
        case .newTrip:
            return "Creates the trip with selected games and options".localized
        case .addToExistingTrip:
            return "Adds the selected game to this trip".localized
        }
    }

    private var gamesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Games to play".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text("Choose one or more games for this trip. You can add more later.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)

                ForEach(viewModel.selectableGameTypes, id: \.self) { gameType in
                    GameTypeSetupRow(
                        gameType: gameType,
                        isSelected: viewModel.selectedGameTypes.contains(gameType),
                        onToggle: { viewModel.toggleGameType(gameType) }
                    )
                }

                Text("Play style applies to each selected game.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Play style applies to each selected game.".localized)

                Picker(selection: defaultGameModeBinding) {
                    Text("Collaborative".localized).tag(GameMode.collaborative)
                    Text("Competitive".localized).tag(GameMode.competitive)
                } label: {
                    Text("Play style".localized)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Game play style".localized)
                .accessibilityHint("Collaborative shares credit. Competitive scores individually.".localized)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Games".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var gameOptionsSection: some View {
        Section {
            VStack(spacing: 12) {
                CountryScopeSection(
                    includeUS: $viewModel.includeUS,
                    includeCanada: $viewModel.includeCanada,
                    includeMexico: $viewModel.includeMexico,
                    includeUSTerritories: $viewModel.includeUSTerritories,
                    includeDC: $viewModel.includeDC,
                    includeCanadianTerritories: $viewModel.includeCanadianTerritories,
                    validationMessage: viewModel.countryValidationMessage,
                    onCountryToggleChanged: { viewModel.applyTerritoryGatingFromCountryToggles() }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Game Options".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Spacer(minLength: 8)
                if viewModel.usesGameDefaultOptions {
                    Text("Using default options".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.permissionOrange.opacity(0.7))
                        .accessibilityLabel("Using default options".localized)
                }
            }
        }
        .textCase(nil)
    }

    private func primaryActionTapped() {
        FeedbackService.shared.buttonTap()
        viewModel.clearError()

        switch viewModel.context {
        case .newTrip:
            guard !viewModel.isSubmitting else { return }
            viewModel.beginSubmitting()
            Task { @MainActor in
                defer { viewModel.endSubmitting() }
                do {
                    let session = try viewModel.createTrip()
                    let inviteFailures = await viewModel.sendSetupInvites(for: session)
                    await viewModel.publishCanonicalToRemote(session: session)
                    if inviteFailures > 0 {
                        pendingCreatedSession = session
                        viewModel.showInvitePartialFailureAlert = true
                        FeedbackService.shared.actionError()
                        return
                    }
                    FeedbackService.shared.actionSuccess()
                    finishCreatedTrip(session)
                } catch {
                    if error is TripEntitlementGateError {
                        tripLimitPaywallViewModel.setTripLimitContext()
                        // F-7 owner UX: a sheet is presenting — neutral feel for the
                        // child informational variant instead of an error buzz.
                        if childPostures.arePurchasesSuppressed {
                            FeedbackService.shared.buttonTap()
                        } else {
                            FeedbackService.shared.actionError()
                        }
                        return
                    }
                    viewModel.setError(error.localizedDescription)
                    FeedbackService.shared.actionError()
                }
            }

        case .addToExistingTrip:
            do {
                _ = try viewModel.addGame()
                onAdded?()
                if viewModel.errorMessage == nil {
                    FeedbackService.shared.actionSuccess()
                    dismiss()
                } else {
                    FeedbackService.shared.actionError()
                }
            } catch {
                viewModel.setError(error.localizedDescription)
                FeedbackService.shared.actionError()
            }
        }
    }

    private func finishCreatedTrip(_ session: TripSession) {
        pendingCreatedSession = nil
        onCreated?(session)
        if onCreated == nil {
            dismiss()
        }
    }
}

struct GameTypeSetupRow: View {
    let gameType: GameType
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gameType.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    if let desc = gameType.shortDescription {
                        Text(desc)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.Theme.primaryBlue : Color.Theme.softBrown)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Theme.background)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(gameType.displayName)
        .accessibilityValue(isSelected ? "Selected".localized : "Not selected".localized)
        .accessibilityHint("Toggle this game for the trip".localized)
    }
}

#Preview("Game Setup - New Trip") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    let draft = TripSetupDraft(
        tripName: "",
        selectedPassengerIds: [],
        startTripRightAway: false,
        skipVoiceConfirmation: false,
        holdToTalk: true,
        saveLocationWhenMarkingPlates: true,
        showMyLocationOnLargeMap: true,
        trackMyLocationDuringTrip: true,
        showMyActiveTripOnLargeMap: true,
        showMyActiveTripOnSmallMap: true
    )
    return NavigationStack {
        GameSetupView(
            viewModel: GameSetupViewModel(
                context: .newTrip(draft),
                tripSessionRepository: TripSessionRepository.shared,
                gameInstanceRepository: GameInstanceRepository.shared,
                authService: auth
            )
        )
    }
    .environmentObject(auth)
    .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}

#Preview("Game Setup - Add Game") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return NavigationStack {
        GameSetupView(
            viewModel: GameSetupViewModel(
                context: .addToExistingTrip(sessionId: UUID()),
                tripSessionRepository: TripSessionRepository.shared,
                gameInstanceRepository: GameInstanceRepository.shared,
                authService: auth
            )
        )
    }
    .environmentObject(auth)
    .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}
