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
    @StateObject private var viewModel: TripSessionViewModel

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
    }

    private func content(session: TripSession) -> some View {
        List {
            Section {
                tripStatusRow(session: session)
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
    }

    private func tripStatusRow(session: TripSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status: \(session.status.rawValue.capitalized)".localized)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("Participants: \(session.participants.count)".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
    }
}
