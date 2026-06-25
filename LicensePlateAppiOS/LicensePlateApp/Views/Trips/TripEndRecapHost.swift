//
//  TripEndRecapHost.swift
//  LicensePlateApp
//
//  Root-level post-end recap presentation (sheet, toast, remote sync hooks).
//

import SwiftUI

/// Wraps home content with trip summary sheet, loading overlay, and remote-end handlers.
struct TripEndRecapHost<Content: View>: View {
    @ObservedObject var mainCoordinator: MainCoordinator
    @ObservedObject var travelLogViewModel: TravelLogViewModel
    @ObservedObject var activeTripsListViewModel: ActiveTripsListViewModel
    @EnvironmentObject private var authService: FirebaseAuthService
    @Environment(\.scenePhase) private var scenePhase

    @State private var tripEndedRemoteToastMessage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay {
                TripSummaryPresentationHost(viewModel: travelLogViewModel)
            }
            .overlay {
                if travelLogViewModel.isLoadingSummary && travelLogViewModel.presentsSummaryAtRoot {
                    ZStack {
                        Color.Theme.background.opacity(0.88)
                            .ignoresSafeArea()
                        ProgressView()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading…".localized)
                }
            }
            .overlay(alignment: .top) {
                if let message = tripEndedRemoteToastMessage {
                    TripEndedRemoteToastBanner(message: message)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation {
                                    tripEndedRemoteToastMessage = nil
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: tripEndedRemoteToastMessage)
            .onChange(of: mainCoordinator.pendingPostEndSummarySessionId) { _, sessionId in
                guard let sessionId else { return }
                travelLogViewModel.openSummary(sessionId: sessionId, source: .localEnd)
                mainCoordinator.clearPendingPostEndSummary()
            }
            .onReceive(TripCanonicalRemoteSyncService.shared.tripEndedRemotelySignal) { info in
                presentRemoteTripRecap(sessionId: info.sessionId, endedBy: info.endedBy)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reconcileAndPresentPendingTripRecaps()
                }
            }
            .onAppear {
                reconcileAndPresentPendingTripRecaps()
            }
    }

    private func currentUserId() -> String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    private func reloadActiveTripsList() {
        activeTripsListViewModel.load(userId: currentUserId())
        TripEndRecapSupport.startMultiplayerListeners(for: activeTripsListViewModel.items)
    }

    private func presentRemoteTripRecap(sessionId: UUID, endedBy: String?) {
        reloadActiveTripsList()
        if let endedBy, endedBy != currentUserId() {
            tripEndedRemoteToastMessage = "trip_end.remote_toast.generic".localized
            AnalyticsService.shared.log(.tripEndedRemoteToastShown(sessionId: sessionId.uuidString))
        }
        if scenePhase == .active {
            travelLogViewModel.openSummary(sessionId: sessionId, source: .remoteEnd)
        } else {
            travelLogViewModel.enqueuePendingAutoRecap(sessionId: sessionId)
        }
    }

    private func reconcileAndPresentPendingTripRecaps() {
        if let infos = try? TripSessionLifecycleService.shared.reconcileRemoteTripEndedFromEventLog(userId: currentUserId()) {
            for info in infos {
                presentRemoteTripRecap(sessionId: info.sessionId, endedBy: info.endedBy)
            }
        }
        travelLogViewModel.flushPendingAutoRecapPresentations()
    }
}

enum TripEndRecapSupport {
    static func startMultiplayerListeners(for items: [ActiveListItem]) {
        for item in items where item.session.status == .active {
            TripCanonicalRemoteSyncService.shared.startIncrementalListeningIfNeeded(sessionId: item.session.id)
        }
    }
}

/// Root-level trip summary sheet + recap error alert (post-end auto-present only).
private struct TripSummaryPresentationHost: View {
    @ObservedObject var viewModel: TravelLogViewModel

    private var rootSummaryBinding: Binding<TripSummary?> {
        Binding(
            get: {
                guard viewModel.presentsSummaryAtRoot else { return nil }
                return viewModel.selectedSummary
            },
            set: { newValue in
                if newValue == nil { viewModel.clearSelection() }
            }
        )
    }

    private var showsRootSummaryError: Binding<Bool> {
        Binding(
            get: { viewModel.summaryErrorMessage != nil && viewModel.presentsSummaryAtRoot },
            set: { if !$0 { viewModel.summaryErrorMessage = nil } }
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert("Error".localized, isPresented: showsRootSummaryError) {
                Button("OK".localized, role: .cancel) {
                    viewModel.summaryErrorMessage = nil
                }
            } message: {
                Text(viewModel.summaryErrorMessage ?? "")
            }
            .sheet(item: rootSummaryBinding) { summary in
                TripSummarySheetContent(viewModel: viewModel, summary: summary)
            }
    }
}

/// Shared recap sheet used from Travel Log and from home auto-present.
struct TripSummarySheetContent: View {
    @ObservedObject var viewModel: TravelLogViewModel
    let summary: TripSummary

    var body: some View {
        NavigationStack {
            TripSummaryView(
                summary: summary,
                currentUserId: viewModel.currentUserId,
                shouldShowAd: viewModel.shouldShowTripSummaryAd()
            ) {
                viewModel.clearSelection()
            }
            .onAppear {
                viewModel.onRecapSheetAppeared(summary: summary)
            }
        }
    }
}
