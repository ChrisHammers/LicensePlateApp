//
//  TripSessionView.swift
//  LicensePlateApp
//
//  Step 6.8 — Trip dashboard: name, status, participants, game list. Tap game → coordinator.openGame (no NavigationLink).
//  Trip map header: found/total across all license-plate games; End ends the trip.
//

import SwiftUI
import MapKit
import CoreLocation
import GoogleMaps

struct TripSessionView: View {
    let sessionId: UUID

    @EnvironmentObject private var coordinator: MainCoordinator
    @EnvironmentObject private var authService: FirebaseAuthService
    @StateObject private var viewModel: TripSessionViewModel
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var showTripSettings = false
    @State private var showPassengerList = false
    @State private var isShowingGameSetup = false
    @State private var showEndTripConfirmation = false
    @State private var showFullScreenMap = false
    @State private var chipWidth: CGFloat = 0
    @State private var chipHeight: CGFloat = 0
    @State private var retryAction: (() -> Void)?
    @State private var visibleCountry: PlateRegion.Country = .unitedStates
    @State private var cameraPosition: GMSCameraPosition = {
        let center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
        return GMSCameraPosition.from(coordinate: center, zoom: 4.0)
    }()
    @Namespace private var mapNamespace

    init(sessionId: UUID, authService: FirebaseAuthService) {
        self.sessionId = sessionId
        _viewModel = StateObject(wrappedValue: TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            lifecycleService: TripSessionLifecycleService.shared,
            authService: authService
        ))
    }

    /// Preview / tests: inject a pre-configured view model (e.g. mocks).
    init(sessionId: UUID, viewModel: TripSessionViewModel) {
        self.sessionId = sessionId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        AppBackgroundView {
            Group {
                if let session = viewModel.session {
                    content(session: session)
                } else {
                    TripMissingView()
                }
            }
        }
        .navigationTitle(viewModel.session?.name ?? "Trip".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showFullScreenMap ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            viewModel.load()
            requestLocationIfNeeded()
            initializeCameraIfNeeded()
        }
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil; retryAction = nil } }
        )) {
            Button("OK".localized, role: .cancel) {
                viewModel.errorMessage = nil
                retryAction = nil
            }
            if retryAction != nil {
                Button("Retry".localized) {
                    retryAction?()
                    viewModel.errorMessage = nil
                    retryAction = nil
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay {
            if showFullScreenMap {
                FullScreenMapView(
                    tripSessionId: sessionId,
                    enabledCountries: mapEnabledCountries,
                    foundRegionIDs: viewModel.tripFoundRegionIDs,
                    foundRegions: viewModel.tripFoundRegions,
                    finderIdentities: viewModel.tripFinderIdentitiesByUserId,
                    cameraPosition: $cameraPosition,
                    locationManager: locationManager,
                    namespace: mapNamespace,
                    isPresented: $showFullScreenMap
                )
                .accessibleTransition(.opacity)
                .zIndex(1000)
            }
        }
    }

    private var mapEnabledCountries: [PlateRegion.Country] {
        if viewModel.tripEnabledCountries.isEmpty {
            return [.unitedStates, .canada, .mexico]
        }
        return viewModel.tripEnabledCountries
    }

    private func content(session: TripSession) -> some View {
        VStack(spacing: 0) {
            tripMapHeader

            List {
                Section {
                    tripStatusRow(session: session)
                    Button {
                        FeedbackService.shared.buttonTap()
                        showPassengerList = true
                    } label: {
                        HStack {
                            Text("Driver & Passengers".localized)
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
                .listRowBackground(Color.Theme.cardBackground)

                if viewModel.showsTripCompetitiveLeaderboard, !viewModel.tripLeaderboardRows.isEmpty {
                    TripSessionLeaderboardSection(
                        gameRowCount: viewModel.gameRowItems.count,
                        rows: viewModel.tripLeaderboardRows,
                        currentUserId: authService.currentUser?.firebaseUID ?? authService.currentUser?.id
                    )
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
                        isShowingGameSetup = true
                    } label: {
                        Label("Add Game".localized, systemImage: "plus.circle")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .disabled(!viewModel.canAddGame)
                    .opacity(viewModel.canAddGame ? 1.0 : 0.5)
                    .accessibilityHint(viewModel.addGameAccessibilityHint)
                    .listRowBackground(Color.Theme.cardBackground)
                } header: {
                    Text("Games".localized)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
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
                .accessibilityHint("Trip name, tracking and privacy, start or end trip, delete trip, or leave trip if you are a passenger".localized)
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
                },
                onTripLeft: {
                    coordinator.pop()
                },
                onTripEnded: { sessionId in
                    coordinator.completeTripEndFlow(sessionId: sessionId)
                }
            )
            .environmentObject(authService)
        }
        .sheet(isPresented: $showPassengerList) {
            TripParticipantsView(sessionId: session.id, authService: authService)
                .environmentObject(authService)
        }
        .sheet(isPresented: $isShowingGameSetup) {
            NavigationStack {
                GameSetupView(
                    viewModel: GameSetupViewModel(
                        context: .addToExistingTrip(sessionId: session.id),
                        tripSessionRepository: TripSessionRepository.shared,
                        gameInstanceRepository: GameInstanceRepository.shared,
                        authService: authService
                    ),
                    onAdded: {
                        viewModel.load()
                    }
                )
            }
            .environmentObject(authService)
        }
        .onChange(of: showTripSettings) { _, isPresented in
            if !isPresented {
                viewModel.load()
            }
        }
        .alert("End Trip".localized, isPresented: $showEndTripConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("End Trip".localized, role: .destructive) {
                performEndTrip()
            }
        } message: {
            Text("This ends the trip and all open games. Make sure all participants have synced so all discoveries are counted.".localized)
        }
    }

    // MARK: - Trip map header

    private var tripMapHeader: some View {
        VStack(spacing: 16) {
            RegionMapView(
                tripSessionId: sessionId,
                enabledCountries: mapEnabledCountries,
                foundRegionIDs: viewModel.tripFoundRegionIDs,
                foundRegions: viewModel.tripFoundRegions,
                visibleCountry: visibleCountry,
                cameraPosition: $cameraPosition,
                namespace: mapNamespace,
                showFullScreen: $showFullScreenMap,
                locationManager: locationManager
            )
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 32)
            .accessibilityLabel("Trip map".localized)
            .accessibilityHint("Shows plates found across all games on this trip".localized)

            HStack(spacing: 24) {
                summaryChip(
                    title: "Found".localized,
                    value: "\(viewModel.tripFoundCount)",
                    measuredWidth: $chipWidth,
                    measuredHeight: $chipHeight
                )
                startEndTripButton(height: chipHeight)
                summaryChip(
                    title: "Total".localized,
                    value: "\(viewModel.tripTotalCount)",
                    measuredWidth: $chipWidth,
                    measuredHeight: $chipHeight
                )
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .padding(.horizontal, 12)
        )
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private struct ChipSizePreference: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = CGSize(
                width: max(value.width, nextValue().width),
                height: max(value.height, nextValue().height)
            )
        }
    }

    private func summaryChip(
        title: String,
        value: String,
        measuredWidth: Binding<CGFloat>,
        measuredHeight: Binding<CGFloat>
    ) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .lineLimit(1)
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(Color.Theme.softBrown)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ChipSizePreference.self, value: geometry.size)
            }
        )
        .frame(
            width: measuredWidth.wrappedValue > 0 ? measuredWidth.wrappedValue : nil,
            height: measuredHeight.wrappedValue > 0 ? measuredHeight.wrappedValue : nil
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.Theme.background)
        )
        .onPreferenceChange(ChipSizePreference.self) { size in
            if size.width > measuredWidth.wrappedValue {
                measuredWidth.wrappedValue = size.width
            }
            if size.height > measuredHeight.wrappedValue {
                measuredHeight.wrappedValue = size.height
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func startEndTripButton(height: CGFloat) -> some View {
        Group {
            if let session = viewModel.session,
               session.status == .ended || session.status == .cancelled {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityHidden(true)
                    Text(session.status == .cancelled ? "CANCELLED".localized : "ENDED".localized)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nil)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityLabel(session.status == .cancelled ? "Trip cancelled".localized : "Trip ended".localized)
                .accessibilityValue(session.status == .cancelled ? "This trip was cancelled".localized : "This trip has ended".localized)
                .accessibilityAddTraits(.isStaticText)
            } else if !viewModel.isTripContainerActive {
                VStack(spacing: 6) {
                    Image(systemName: "car.circle")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityHidden(true)
                    Text("Trip not started".localized)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nil)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Trip not started".localized)
                .accessibilityValue("Start the trip from trip settings before ending it".localized)
                .accessibilityAddTraits(.isStaticText)
            } else {
                Button {
                    FeedbackService.shared.buttonTap()
                    showEndTripConfirmation = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                        Text("END".localized)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canEndTrip)
                .opacity(viewModel.canEndTrip ? 1.0 : 0.5)
                .frame(height: height > 0 ? height : nil)
                .accessibilityLabel("End Trip".localized)
                .accessibilityHint(viewModel.endTripAccessibilityHint)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func performEndTrip() {
        do {
            try viewModel.endTrip()
            coordinator.completeTripEndFlow(sessionId: sessionId)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            retryAction = {
                do {
                    try viewModel.endTrip()
                    coordinator.completeTripEndFlow(sessionId: sessionId)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestLocationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
        }
    }

    private func initializeCameraIfNeeded() {
        let countries = mapEnabledCountries
        visibleCountry = countries.first ?? .unitedStates
        let center: CLLocationCoordinate2D
        let zoom: Float
        if countries.count == 1, let only = countries.first {
            switch only {
            case .unitedStates:
                center = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
                zoom = 3.5
            case .canada:
                center = CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468)
                zoom = 3.0
            case .mexico:
                center = CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528)
                zoom = 4.5
            }
        } else {
            center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
            zoom = 3.2
        }
        cameraPosition = GMSCameraPosition.from(coordinate: center, zoom: zoom)
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

// MARK: - Trip-wide competitive leaderboard (Step 12)

private struct TripSessionLeaderboardSection: View {
    let gameRowCount: Int
    let rows: [RankedParticipantContribution]
    let currentUserId: String?
    @State private var displayNames: [String: String] = [:]

    var body: some View {
        Section {
            ForEach(rows) { row in
                let c = row.contribution
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Rank #%d".localized(row.rank))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(minWidth: 56, alignment: .leading)
                    if row.isTiedOnScore {
                        Text("Tied".localized)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Text(displayName(for: c.participantId))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer(minLength: 4)
                    Text("%d first finds".localized(c.firstFindCount))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text("\(c.discoveryCount) found".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text(String(format: "%.1f", c.weightedScore))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(leaderboardRowAccessibilityLabel(row: row))
                .listRowBackground(Color.Theme.cardBackground)
            }
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Trip leaderboard".localized)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityAddTraits(.isHeader)
                if gameRowCount > 1 {
                    Text("Scores and finds combine all games on this trip.".localized)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Scores and finds combine all games on this trip.".localized)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textCase(nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trip leaderboard".localized)
        .task(id: leaderboardTaskIdentity) {
            let ids = Set(rows.map(\.contribution.participantId))
            displayNames = await UserRepository.shared.displayNames(forUserIds: ids)
        }
    }

    private var leaderboardTaskIdentity: String {
        rows.map { "\($0.contribution.participantId):\($0.rank):\($0.contribution.weightedScore)" }.joined(separator: "|")
    }

    private func displayName(for participantId: String) -> String {
        let name = displayNames[participantId] ?? "Unknown participant".localized
        return ParticipantDisplayName.decorated(
            name,
            userId: participantId,
            currentUserId: currentUserId
        )
    }

    private func leaderboardRowAccessibilityLabel(row: RankedParticipantContribution) -> String {
        let c = row.contribution
        let name = displayName(for: c.participantId)
        var parts: [String] = [name]
        parts.append("Rank #%d".localized(row.rank))
        if row.isTiedOnScore { parts.append("Tied".localized) }
        parts.append("%d first finds".localized(c.firstFindCount))
        parts.append("\(c.discoveryCount) found".localized)
        parts.append(String(format: "%.1f", c.weightedScore))
        return parts.joined(separator: ", ")
    }
}

private struct GameRowView: View {
    let item: GameRowItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    if item.showsInProgressIndicator {
                        Text("In progress".localized)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.Theme.primaryBlue.opacity(0.12))
                            )
                            .accessibilityLabel("In progress".localized)
                    }
                }
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
                Text(item.gameTypeDisplay)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.85))
                    .accessibilityLabel("Game type".localized + ", " + item.gameTypeDisplay)
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

#Preview("Trip session — active driver") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: PreviewConstants.userId1, userName: "Preview Driver", firebaseUID: PreviewConstants.userId1)
    return NavigationStack {
        TripSessionView(sessionId: PreviewConstants.sessionIdSolo, authService: auth)
            .environmentObject(MainCoordinator())
            .environmentObject(auth)
    }
}

#Preview("Trip session — passenger") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: PreviewConstants.userId2, userName: "Preview Passenger", firebaseUID: PreviewConstants.userId2)
    return NavigationStack {
        TripSessionView(sessionId: PreviewConstants.sessionIdSolo, authService: auth)
            .environmentObject(MainCoordinator())
            .environmentObject(auth)
    }
}

#Preview("Trip session — ended") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: PreviewConstants.userId1, userName: "Preview Driver", firebaseUID: PreviewConstants.userId1)
    return NavigationStack {
        TripSessionView(sessionId: PreviewConstants.sessionIdSolo, authService: auth)
            .environmentObject(MainCoordinator())
            .environmentObject(auth)
    }
}

#Preview("Trip leaderboard — tied standings") {
    List {
        TripSessionLeaderboardSection(
            gameRowCount: 2,
            rows: PreviewSummaryFixtures.tripSummaryCompetitiveTied().rankedParticipants,
            currentUserId: nil
        )
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.Theme.background)
}
