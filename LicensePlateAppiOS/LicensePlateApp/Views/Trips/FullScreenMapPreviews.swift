//
//  FullScreenMapPreviews.swift
//  LicensePlateApp
//
//  Where-found pin previews kept out of `LicensePlateGameView.swift` so the canvas
//  can render without timing out on the full game screen file (same pattern as
//  `LicensePlateRegionRowPreviews.swift`). Apple Maps path only — GMSMapView
//  requires the Maps SDK to boot, which the canvas process never does.
//

import SwiftUI

#Preview("Where-found pins — all located") {
    FullScreenAppleMapPreviewHost(foundRegions: PreviewLocationFixtures.foundRegionsWithLocations())
}

#Preview("Where-found pins — mixed (some without location)") {
    FullScreenAppleMapPreviewHost(foundRegions: PreviewLocationFixtures.foundRegionsMixedLocations())
}

#Preview("Where-found pins — multiplayer finders") {
    FullScreenAppleMapPreviewHost(
        foundRegions: PreviewLocationFixtures.foundRegionsWithLocations(),
        finderIdentities: PreviewLocationFixtures.finderIdentities()
    )
}

private struct FullScreenAppleMapPreviewHost: View {
    let foundRegions: [FoundRegion]
    var finderIdentities: [String: UserRepository.UserIdentitySnapshot] = [:]
    @Namespace private var namespace
    @State private var isPresented = true

    var body: some View {
        // No FirebaseAuthService environment object: constructing it requires a configured
        // FirebaseApp, which the canvas process never has. The view only reads it inside the
        // user-location annotation, which cannot render in previews (no location fix).
        FullScreenAppleMapView(
            country: .unitedStates,
            foundRegionIDs: foundRegions.map(\.regionID),
            foundRegions: foundRegions,
            finderIdentities: finderIdentities,
            locationManager: LocationManager.shared,
            namespace: namespace,
            isPresented: $isPresented
        )
    }
}
