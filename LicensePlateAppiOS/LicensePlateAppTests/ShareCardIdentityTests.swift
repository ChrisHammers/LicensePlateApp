//
//  ShareCardIdentityTests.swift
//  LicensePlateAppTests
//
//  v4 FR-100 (F-60): the exported share image carries no personal information, at any
//  age. (a) the OD-10 two-outcome matrix in both directions, the identical-render
//  proof for child vs unresolved, positional (never stable) labels, the no-uid pin;
//  (b) the MapKit prohibition and (c) the EXIF absence, pinned as tests.
//

import Foundation
import ImageIO
import UIKit
import Testing
@testable import LicensePlateApp

@MainActor
struct ShareCardIdentityTests {

    private func summary(participants: [String]) -> TripSummary {
        var summary = PreviewSummaryFixtures.tripSummarySolo()
        summary.rankedParticipants = participants.enumerated().map { index, uid in
            RankedParticipantContribution(
                contribution: ParticipantContribution(
                    participantId: uid,
                    discoveryCount: 5 - index,
                    weightedScore: Double(5 - index),
                    firstFindCount: 0
                ),
                rank: index + 1,
                isTiedOnScore: false
            )
        }
        return summary
    }

    // MARK: - FR-100(a): the OD-10 two-outcome policy, both directions

    @Test func aServerResolvedAdultKeepsTheirName() {
        let evidence = ExportIdentityEvidence(serverResolvedNotChild: true, anyChildEvidence: false)
        #expect(
            IdentityRenderPolicy.exportDisplayName(
                rawDisplayName: "Chris", position: 1, evidence: evidence
            ) == "Chris"
        )
    }

    @Test func childAndUnresolvedRenderIdenticallyAsTheNeutralLabel() {
        // One token for both cases, deliberately: the export must not disclose WHICH
        // reason applied — "this one is a child" is itself information about a child.
        let child = ExportIdentityEvidence(serverResolvedNotChild: false, anyChildEvidence: true)
        let unresolved = ExportIdentityEvidence(serverResolvedNotChild: false, anyChildEvidence: false)
        let childToken = IdentityRenderPolicy.exportDisplayName(
            rawDisplayName: "KidRacer", position: 2, evidence: child
        )
        let unresolvedToken = IdentityRenderPolicy.exportDisplayName(
            rawDisplayName: "SomeName", position: 2, evidence: unresolved
        )
        #expect(childToken == unresolvedToken)
        #expect(childToken == IdentityRenderPolicy.neutralLabel(position: 2))
        #expect(!childToken.contains("KidRacer"))
    }

    @Test func childEvidenceBeatsAStaleNotChildResolution() {
        // Asymmetric trust: ANY child evidence wins over a resolved-false signal.
        let conflicted = ExportIdentityEvidence(serverResolvedNotChild: true, anyChildEvidence: true)
        #expect(
            IdentityRenderPolicy.exportDisplayName(
                rawDisplayName: "Chris", position: 3, evidence: conflicted
            ) == IdentityRenderPolicy.neutralLabel(position: 3)
        )
    }

    @Test func aResolvedAdultWithNoHydratedNameStillNeverLeaksAnything() {
        let evidence = ExportIdentityEvidence(serverResolvedNotChild: true, anyChildEvidence: false)
        #expect(
            IdentityRenderPolicy.exportDisplayName(
                rawDisplayName: nil, position: 1, evidence: evidence
            ) == IdentityRenderPolicy.neutralLabel(position: 1)
        )
        #expect(
            IdentityRenderPolicy.exportDisplayName(
                rawDisplayName: "", position: 1, evidence: evidence
            ) == IdentityRenderPolicy.neutralLabel(position: 1)
        )
    }

    // MARK: - The resolver against live-shaped session state

    @Test func resolverMapsAdultsChildrenAndUnresolvedPerSubject() {
        let userRepository = UserRepository()
        let familyRepository = FamilyRepository()
        // adult-1: server-resolved this session, not a child (absent key on a real doc).
        userRepository.ingestChildAccountResolution(
            userId: "adult-1",
            UserRepository.ChildAccountResolution(isChild: false, isServerExplicit: false)
        )
        // kid-2: the family projection flags them; no user-doc resolution at all.
        familyRepository.applyChildMemberFlags(["kid-2": true], familyId: "fam-1")
        // ghost-3: nothing known anywhere.

        let tokens = ShareCardIdentityResolver.exportDisplayNames(
            summary: summary(participants: ["adult-1", "kid-2", "ghost-3"]),
            currentUserId: "adult-1",
            hydratedDisplayNames: [
                "adult-1": "Chris", "kid-2": "KidRacer", "ghost-3": "Mystery",
            ],
            userRepository: userRepository,
            familyRepository: familyRepository,
            currentSessionChildRestricted: false
        )

        #expect(tokens["adult-1"] == "Chris")
        #expect(tokens["kid-2"] == IdentityRenderPolicy.neutralLabel(position: 2))
        #expect(tokens["ghost-3"] == IdentityRenderPolicy.neutralLabel(position: 3))
        // No token value may carry a raw uid.
        #expect(!tokens.values.contains { $0.contains("kid-2") || $0.contains("ghost-3") })
    }

    @Test func theSharersOwnChildPostureNeutralizesTheirOwnRowOnly() {
        let userRepository = UserRepository()
        userRepository.ingestChildAccountResolution(
            userId: "adult-2",
            UserRepository.ChildAccountResolution(isChild: false, isServerExplicit: false)
        )

        let tokens = ShareCardIdentityResolver.exportDisplayNames(
            summary: summary(participants: ["me-child", "adult-2"]),
            currentUserId: "me-child",
            hydratedDisplayNames: ["me-child": "LocalKid", "adult-2": "Blake"],
            userRepository: userRepository,
            familyRepository: FamilyRepository(),
            currentSessionChildRestricted: true
        )

        #expect(tokens["me-child"] == IdentityRenderPolicy.neutralLabel(position: 1))
        #expect(tokens["adult-2"] == "Blake")
    }

    @Test func labelsArePositionalNeverAStablePseudonym() {
        // The same unresolved subject at a different row position gets a DIFFERENT
        // label — a stable one across trips would itself become an identifier.
        let first = ShareCardIdentityResolver.exportDisplayNames(
            summary: summary(participants: ["kid-x", "other"]),
            currentUserId: nil,
            hydratedDisplayNames: [:],
            userRepository: UserRepository(),
            familyRepository: FamilyRepository(),
            currentSessionChildRestricted: false
        )
        let second = ShareCardIdentityResolver.exportDisplayNames(
            summary: summary(participants: ["other", "kid-x"]),
            currentUserId: nil,
            hydratedDisplayNames: [:],
            userRepository: UserRepository(),
            familyRepository: FamilyRepository(),
            currentSessionChildRestricted: false
        )
        #expect(first["kid-x"] == IdentityRenderPolicy.neutralLabel(position: 1))
        #expect(second["kid-x"] == IdentityRenderPolicy.neutralLabel(position: 2))
        #expect(first["kid-x"] != second["kid-x"])
    }

    // MARK: - FR-100(b): no map may ever be composed into the export

    /// Standing prohibition, not a toggle: the share card's three files must never
    /// reference a MapKit symbol or the locationMetadata key. Source-scan, like the
    /// FR-101(c) precedent.
    @Test func shareCardFilesReferenceNoMapOrLocationSymbols() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let tripsDir = testsDir.deletingLastPathComponent()
            .appendingPathComponent("LicensePlateApp/Views/Trips")
        let shareFiles = [
            "TripSummaryShareCardView.swift",
            "TripSummaryShareContentBuilder.swift",
            "TripSummaryShareActivityItemSource.swift",
        ]
        for file in shareFiles {
            let source = try String(
                contentsOf: tripsDir.appendingPathComponent(file), encoding: .utf8
            )
            #expect(!source.contains("MapKit"), "\(file) must not import MapKit")
            #expect(!source.contains("MKMap"), "\(file) must not touch MapKit symbols")
            #expect(!source.contains("MapPolyline"), "\(file) must not draw routes")
            #expect(!source.contains("locationMetadata"), "\(file) must not read route metadata")
            #expect(!source.contains("CLLocation"), "\(file) must not touch location types")
        }
    }

    // MARK: - FR-100(c): no location metadata on the exported asset

    @Test func renderedShareImageCarriesNoGPSMetadata() throws {
        let image = try #require(TripSummaryShareImageRenderer.render(
            summary: summary(participants: ["adult-1", "kid-2"]),
            currentUserId: "adult-1",
            participantDisplayNames: ["adult-1": "Chris"]
        ))
        let data = try #require(image.pngData())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gps = properties?[kCGImagePropertyGPSDictionary]
        #expect(gps == nil)
    }
}
