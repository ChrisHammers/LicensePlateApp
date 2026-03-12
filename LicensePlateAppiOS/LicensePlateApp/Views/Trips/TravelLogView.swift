//
//  TravelLogView.swift
//  LicensePlateApp
//
//  Step 07 — Travel Log: list completed/ended trip sessions with key stats; tap to open rich TripSummaryView.
//

import SwiftUI
import SwiftData

struct TravelLogView: View {
    @ObservedObject var viewModel: TravelLogViewModel
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.Theme.accentYellow)
                        Text(message)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error".localized + " " + message)
                } else if viewModel.entries.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Travel Log".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        FeedbackService.shared.buttonTap()
                        dismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Close".localized)
                    .accessibilityHint("Dismiss Travel Log".localized)
                }
            }
            .onAppear {
                viewModel.loadEntries()
                viewModel.onScreenAppeared()
                AnalyticsService.shared.logScreenView(screenName: "travel_log")
            }
            .sheet(item: $viewModel.selectedSummary) { summary in
                NavigationStack {
                    TripSummaryView(summary: summary) {
                        viewModel.clearSelection()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
            Text("No completed trips yet".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("Your completed trips will appear here.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No completed trips yet. Your completed trips will appear here.".localized)
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.entries) { entry in
                TravelLogRowView(entry: entry, dateFormatter: dateFormatter)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.openSummary(sessionId: entry.sessionId)
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                    .accessibilityLabel(accessibilityLabel(for: entry))
                    .accessibilityHint("Double tap to view trip summary".localized)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func accessibilityLabel(for entry: TravelLogEntry) -> String {
        var parts: [String] = [entry.tripName, entry.summary, dateFormatter.string(from: entry.endedAt)]
        if let pc = entry.participantCount, pc > 0 {
            parts.append("\(pc) participants".localized)
        }
        if let gc = entry.gameCount, gc > 0 {
            parts.append("\(gc) games".localized)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Row with key stats
private struct TravelLogRowView: View {
    let entry: TravelLogEntry
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.tripName)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Spacer()
                if let status = entry.status, status == .cancelled {
                    Text("Cancelled".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            if let pc = entry.participantCount, let gc = entry.gameCount, (pc > 0 || gc > 0) {
                HStack(spacing: 12) {
                    if pc > 0 {
                        Label("\(pc) participants".localized, systemImage: "person.2.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    if gc > 0 {
                        Label("\(gc) games".localized, systemImage: "gamecontroller.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
            }
            Text(entry.summary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
            Text(dateFormatter.string(from: entry.endedAt))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.vertical, 8)
    }
}

// TripSummary must be Identifiable for sheet(item:)
extension TripSummary: Identifiable {
    var id: UUID { sessionId }
}

#Preview("Travel Log") {
    TravelLogView(viewModel: TravelLogViewModel(
        travelLogRepository: TravelLogRepository.shared,
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripRepository: TripRepository.shared,
        authService: FirebaseAuthService()
    ))
    .environmentObject(FirebaseAuthService())
    .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self], inMemory: true)
}

#Preview("Travel Log - With entries") {
    TravelLogView(viewModel: TravelLogViewModel(
        travelLogRepository: TravelLogRepository.shared,
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripRepository: TripRepository.shared,
        authService: FirebaseAuthService(),
        previewEntries: [
            PreviewTravelLogFixtures.travelLogEntry(),
            PreviewTravelLogFixtures.travelLogEntryWithSummaries()
        ]
    ))
    .environmentObject(FirebaseAuthService())
    .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self], inMemory: true)
}
