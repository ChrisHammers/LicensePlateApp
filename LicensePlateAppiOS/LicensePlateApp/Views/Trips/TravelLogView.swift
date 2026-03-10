//
//  TravelLogView.swift
//  LicensePlateApp
//
//  Step 04 — Placeholder Travel Log: lists completed trip sessions from TravelLogRepository.
//

import SwiftUI
import SwiftData

struct TravelLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var entries: [TravelLogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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

                if isLoading {
                    ProgressView()
                } else if entries.isEmpty {
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
                } else {
                    List {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.tripName)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                Text(entry.summary)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                Text(dateFormatter.string(from: entry.endedAt))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            .padding(.vertical, 8)
                            .listRowBackground(Color.Theme.cardBackground)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
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
                }
            }
            .onAppear {
                loadEntries()
            }
        }
    }

    private func loadEntries() {
        isLoading = true
        errorMessage = nil
        TravelLogRepository.shared.setModelContext(modelContext)
        let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        do {
            entries = try TravelLogRepository.shared.getSummaryProjections(
                userId: userId,
                sortBy: .endedAtDesc,
                limit: 100
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    TravelLogView()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: TripSessionEntity.self, inMemory: true)
}
