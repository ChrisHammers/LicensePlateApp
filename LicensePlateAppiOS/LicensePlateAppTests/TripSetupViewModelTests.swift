//
//  TripSetupViewModelTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSetupViewModelTests {

    private final class StubNewTripDefaultsStore: NewTripDefaultsStoring {
        private let snapshot: NewTripDefaults

        init(snapshot: NewTripDefaults) {
            self.snapshot = snapshot
        }

        func load() -> NewTripDefaults { snapshot }
        func save(_ snapshot: NewTripDefaults) {}
    }

    private func makeDefaults(startTripRightAway: Bool) -> NewTripDefaults {
        NewTripDefaults(
            includeUS: true,
            includeCanada: false,
            includeMexico: true,
            startTripRightAway: startTripRightAway,
            skipVoiceConfirmation: true,
            holdToTalk: false,
            saveLocationWhenMarkingPlates: false,
            showMyLocationOnLargeMap: false,
            trackMyLocationDuringTrip: false,
            showMyActiveTripOnLargeMap: false,
            showMyActiveTripOnSmallMap: false
        )
    }

    @Test func initAppliesNewTripDefaults() async throws {
        let auth = FirebaseAuthService()
        let viewModel = TripSetupViewModel(
            authService: auth,
            newTripDefaultsStore: StubNewTripDefaultsStore(snapshot: makeDefaults(startTripRightAway: true))
        )

        #expect(viewModel.includeUS == true)
        #expect(viewModel.includeCanada == false)
        #expect(viewModel.includeMexico == true)
        #expect(viewModel.startTripRightAway == true)
        #expect(viewModel.skipVoiceConfirmation == true)
        #expect(viewModel.holdToTalk == false)
        #expect(viewModel.saveLocationWhenMarkingPlates == false)
    }

    @Test func canProceedRequiresAtLeastOneCountry() async throws {
        let auth = FirebaseAuthService()
        let viewModel = TripSetupViewModel(authService: auth)
        viewModel.includeUS = true
        #expect(viewModel.canProceed == true)

        viewModel.includeUS = false
        viewModel.includeCanada = false
        viewModel.includeMexico = false
        #expect(viewModel.canProceed == false)
        #expect(viewModel.countryValidationMessage == "Select at least one country.".localized)
    }

    @Test func buildDraftCapturesTripFields() async throws {
        let auth = FirebaseAuthService()
        let viewModel = TripSetupViewModel(authService: auth)
        viewModel.tripName = "Weekend"
        viewModel.selectedPassengerIds = ["friend1"]
        viewModel.includeUS = true
        viewModel.includeCanada = false
        viewModel.startTripRightAway = true

        let draft = viewModel.buildDraft()
        #expect(draft.tripName == "Weekend")
        #expect(draft.selectedPassengerIds == ["friend1"])
        #expect(draft.enabledCountries == [.unitedStates])
        #expect(draft.startTripRightAway == true)
    }
}
