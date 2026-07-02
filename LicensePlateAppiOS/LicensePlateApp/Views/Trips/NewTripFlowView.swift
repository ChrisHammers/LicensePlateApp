//
//  NewTripFlowView.swift
//  LicensePlateApp
//
//  Two-step new trip flow: TripSetup → GameSetup.
//

import SwiftUI
import SwiftData

struct NewTripFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FirebaseAuthService

    @StateObject private var tripSetupViewModel: TripSetupViewModel
    @State private var navigationPath = NavigationPath()

    var onCreated: (TripSession) -> Void

    init(authService: FirebaseAuthService, onCreated: @escaping (TripSession) -> Void) {
        _tripSetupViewModel = StateObject(wrappedValue: TripSetupViewModel(authService: authService))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TripSetupView(
                viewModel: tripSetupViewModel,
                onNext: {
                    let draft = tripSetupViewModel.buildDraft()
                    navigationPath.append(NewTripFlowRoute.gameSetup(draft))
                },
                onCancel: {
                    FeedbackService.shared.buttonTap()
                    dismiss()
                }
            )
            .navigationDestination(for: NewTripFlowRoute.self) { route in
                switch route {
                case .gameSetup(let draft):
                    GameSetupView(
                        viewModel: GameSetupViewModel(
                            context: .newTrip(draft),
                            tripSessionRepository: TripSessionRepository.shared,
                            gameInstanceRepository: GameInstanceRepository.shared,
                            authService: authService
                        ),
                        onCreated: { session in
                            onCreated(session)
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

private enum NewTripFlowRoute: Hashable {
    case gameSetup(TripSetupDraft)
}

#Preview("New Trip Flow") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return NewTripFlowView(authService: auth, onCreated: { _ in })
        .environmentObject(auth)
        .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}
