//
//  TripSettingsView.swift
//  LicensePlateApp
//
//  Step 6.9.3.1 — Trip-level settings: name, start/end trip, delete trip. Opened from TripSessionView.
//

import SwiftUI

struct TripSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TripSettingsViewModel
    var onTripDeleted: () -> Void
    var onTripLeft: () -> Void

    @State private var showEndTripConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showLeaveTripConfirmation = false
    @State private var retryAction: (() -> Void)?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                List {
                    Section {
                        VStack {
                            tripInfoContent
                        }
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                    } header: {
                        Text("Trip Info".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Trip settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        viewModel.saveSession()
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Saves trip name and dismisses trip settings".localized)
                }
            }
        }
        .background(Color.Theme.background)
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError(); retryAction = nil } }
        )) {
            Button("OK".localized, role: .cancel) {
                viewModel.clearError()
                retryAction = nil
            }
            if retryAction != nil {
                Button("Retry".localized) {
                    retryAction?()
                    viewModel.clearError()
                    retryAction = nil
                }
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }

    private var tripInfoContent: some View {
        Group {
            SettingEditableTextRow(
                title: "Trip Name".localized,
                value: Binding(
                    get: { viewModel.currentSession.name },
                    set: { viewModel.updateTripName($0) }
                ),
                placeholder: "Enter trip name".localized,
                isDisabled: !viewModel.isTripCreator,
                onSave: {
                    viewModel.saveSession()
                },
                onCancel: {}
            )

            Divider()

            if let startedAt = viewModel.currentSession.startedAt {
                SettingInfoRow(
                    title: "Started".localized,
                    value: dateFormatter.string(from: startedAt)
                )
                Divider()
            } else {
                SettingInfoRow(
                    title: "Created".localized,
                    value: dateFormatter.string(from: viewModel.currentSession.createdAt)
                )
                Divider()
            }

            if viewModel.currentSession.startedAt == nil {
                Button {
                    do {
                        try viewModel.startTrip()
                    } catch {
                        viewModel.setError(error.localizedDescription)
                        retryAction = { try? viewModel.startTrip() }
                    }
                } label: {
                    HStack {
                        Text("Start Trip".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.Theme.primaryBlue)
                            .frame(maxWidth: .infinity, maxHeight: 50)
                            .padding(.horizontal, 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)
                .opacity(viewModel.isTripCreator ? 1.0 : 0.5)
            }

            Divider()

            if viewModel.currentSession.startedAt != nil && viewModel.currentSession.status == .active {
                Button {
                    showEndTripConfirmation = true
                } label: {
                    HStack {
                        Text("End Trip".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.red)
                            .frame(maxWidth: .infinity, maxHeight: 50)
                            .padding(.horizontal, 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)

                Divider()
            } else if let endedAt = viewModel.currentSession.endedAt {
                SettingInfoRow(
                    title: viewModel.currentSession.status == .cancelled ? "Cancelled".localized : "Ended".localized,
                    value: dateFormatter.string(from: endedAt)
                )
            }

            Divider()

            if viewModel.canLeaveTrip {
                Button {
                    showLeaveTripConfirmation = true
                } label: {
                    HStack {
                        Text("Leave Trip".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave Trip".localized)
                .accessibilityHint("Remove yourself from this trip. Changes sync when online.".localized)

                Divider()
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete Trip".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isTripCreator)
        }
        .alert("End Trip".localized, isPresented: $showEndTripConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("End Trip".localized, role: .destructive) {
                do {
                    try viewModel.endTrip()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.endTrip() }
                }
            }
        } message: {
            Text("This ends the trip. You won't be able to add license plates to this trip anymore.".localized)
        }
        .alert("Delete Trip".localized, isPresented: $showDeleteConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Delete".localized, role: .destructive) {
                do {
                    try viewModel.deleteTrip()
                    dismiss()
                    onTripDeleted()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = {
                        try? viewModel.deleteTrip()
                        dismiss()
                        onTripDeleted()
                    }
                }
            }
        } message: {
            Text("This will delete the trip and all scores will be removed.".localized)
        }
        .alert("Leave Trip".localized, isPresented: $showLeaveTripConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Leave Trip".localized, role: .destructive) {
                do {
                    try viewModel.leaveTrip()
                    dismiss()
                    onTripLeft()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = {
                        try? viewModel.leaveTrip()
                        dismiss()
                        onTripLeft()
                    }
                }
            }
        } message: {
            Text("You will leave this trip on this device right away. If you are offline, leaving the trip will sync when you are back online.".localized)
        }
    }
}

#Preview("Trip settings") {
    let session = TripSession(
        name: "Preview Trip",
        status: .active,
        createdAt: Date(),
        createdBy: "u1",
        startedAt: Date(),
        participants: []
    )
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
    return NavigationStack {
        TripSettingsView(
            viewModel: TripSettingsViewModel(
                session: session,
                tripSessionRepository: TripSessionRepository.shared,
                lifecycleService: TripSessionLifecycleService.shared,
                authService: auth
            ),
            onTripDeleted: {},
            onTripLeft: {}
        )
    }
}

#Preview("Passenger trip settings") {
    let session = TripSession(
        name: "Shared Trip",
        status: .active,
        createdAt: Date(),
        createdBy: "owner1",
        startedAt: Date(),
        participants: [
            TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
            TripParticipant(userId: "u2", role: .member, joinedAt: Date())
        ]
    )
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "u2", userName: "Passenger", firebaseUID: "u2")
    return NavigationStack {
        TripSettingsView(
            viewModel: TripSettingsViewModel(
                session: session,
                tripSessionRepository: TripSessionRepository.shared,
                lifecycleService: TripSessionLifecycleService.shared,
                authService: auth
            ),
            onTripDeleted: {},
            onTripLeft: {}
        )
    }
}
