//
//  TripSessionView.swift
//  LicensePlateApp
//
//  Step 6.8 — Trip dashboard: name, status, participants, game list. Tap game → coordinator.openGame (no NavigationLink).
//

import SwiftUI

struct TripSessionView: View {
    let sessionId: UUID

    @EnvironmentObject private var coordinator: MainCoordinator
    @EnvironmentObject private var authService: FirebaseAuthService
    @StateObject private var viewModel: TripSessionViewModel
    @State private var showTripSettings = false
    @State private var showPassengerList = false

    init(sessionId: UUID) {
        self.sessionId = sessionId
        _viewModel = StateObject(wrappedValue: TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared
        ))
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                content(session: session)
            } else {
                TripMissingView()
            }
        }
        .navigationTitle(viewModel.session?.name ?? "Trip".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
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
    }

    private func content(session: TripSession) -> some View {
        List {
            Section {
                tripStatusRow(session: session)
                Button {
                    FeedbackService.shared.buttonTap()
                    showPassengerList = true
                } label: {
                    HStack {
                        Text("Passenger List".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Spacer()
                        Text("\(session.participants.count)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
            } header: {
                Text("Trip".localized)
            }

            Section {
                ForEach(viewModel.gameRowItems) { item in
                    Button {
                        FeedbackService.shared.buttonTap()
                        coordinator.openGame(sessionId: session.id, gameId: item.gameId)
                    } label: {
                        GameRowView(item: item)
                    }
                    .disabled(!item.isEnterable)
                    .opacity(item.isEnterable ? 1.0 : 0.7)
                    .listRowBackground(Color.Theme.cardBackground)
                }

                Button {
                    FeedbackService.shared.buttonTap()
                    viewModel.addGame()
                } label: {
                    Label("Add Game".localized, systemImage: "plus.circle")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .listRowBackground(Color.Theme.cardBackground)
            } header: {
                Text("Games".localized)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    FeedbackService.shared.buttonTap()
                    viewModel.load()
                    showTripSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .accessibilityLabel("Trip settings".localized)
                .accessibilityHint("Trip name, start or end trip, or delete trip".localized)
            }
        }
        .sheet(isPresented: $showTripSettings) {
            TripSettingsView(
                viewModel: TripSettingsViewModel(
                    session: session,
                    tripSessionRepository: TripSessionRepository.shared,
                    lifecycleService: TripSessionLifecycleService.shared,
                    authService: authService
                ),
                onTripDeleted: {
                    coordinator.pop()
                }
            )
            .environmentObject(authService)
        }
        .sheet(isPresented: $showPassengerList) {
            TripParticipantsView(sessionId: session.id)
                .environmentObject(authService)
        }
        .onChange(of: showTripSettings) { _, isPresented in
            if !isPresented {
                viewModel.load()
            }
        }
    }

    private func tripStatusRow(session: TripSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip status: %@".localized(tripStatusLabel(session.status)))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityLabel("Trip status".localized + ", " + tripStatusLabel(session.status))
            Text("Trip participation: %@".localized(session.mode.localizedDisplayName))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("Trip participation".localized + ", " + session.mode.localizedDisplayName)
            Text("%d games".localized(viewModel.gameRowItems.count))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("%d games".localized(viewModel.gameRowItems.count))
            Text("Participants: %d".localized(session.participants.count))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("Participants: %d".localized(session.participants.count))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func tripStatusLabel(_ status: TripSessionState) -> String {
        switch status {
        case .created: return "Created".localized
        case .active: return "Active".localized
        case .ended: return "Ended".localized
        case .cancelled: return "Cancelled".localized
        }
    }
}

private struct GameRowView: View {
    let item: GameRowItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(item.progressSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                Text("Game mode: %@".localized(item.gameModeDisplay))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Game mode".localized + ", " + item.gameModeDisplay)
                if let teams = item.teamSummary {
                    Text("Teams: %@".localized(teams))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Teams".localized + ", " + teams)
                }
                Text(item.statusOrLifecycle.capitalized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.85))
                    .accessibilityLabel("Game state: %@".localized(item.statusOrLifecycle))
            }
            Spacer()
            if item.isEnterable {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview("Trip session") {
    NavigationStack {
        TripSessionView(sessionId: PreviewConstants.sessionIdSolo)
            .environmentObject(MainCoordinator())
            .environmentObject(FirebaseAuthService())
    }
}
