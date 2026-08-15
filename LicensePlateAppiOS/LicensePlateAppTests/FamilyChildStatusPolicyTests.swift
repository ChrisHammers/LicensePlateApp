//
//  FamilyChildStatusPolicyTests.swift
//  LicensePlateAppTests
//
//  COPPA F-8: pure policy + callable payload shapes. These pin the contract with
//  `childAccountCore.ts` / `familyChildStatusFlows.ts` — a renamed field here is a
//  server rejection in production.
//

import Foundation
import Testing
import FirebaseFunctions
@testable import LicensePlateApp

// MARK: - Consent draft (FR-31)

struct ChildConsentDraftTests {

    @Test func consentIsIncompleteUntilBothBoxesAreChecked() {
        #expect(ChildConsentDraft().isComplete == false)
        #expect(ChildConsentDraft(consentAcknowledged: true).isComplete == false)
        #expect(ChildConsentDraft(guardianAffirmed: true).isComplete == false)
        #expect(
            ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true).isComplete == true
        )
    }

    @Test func expectedAgeOutYearWindowMatchesTheServer() {
        // `validateExpectedAgeOutYear`: nowYear ... nowYear + 13, integers only.
        #expect(ExpectedAgeOutYearOptions.isValid(nil, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.isValid(2026, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.isValid(2039, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(2025, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(2040, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.options(currentYear: 2026).count == 14)
    }

    @Test func correctionReasonsAreExactlyTheTwoServerSlugs() {
        #expect(
            ChildStatusCorrectionReason.allCases.map(\.rawValue)
                == ["flag_set_in_error", "child_turned_13"]
        )
    }
}

// MARK: - Consent-copy policy links (owner change request)

struct ChildConsentPolicyLinkTests {

    @Test func linksResolveFromTheirOwnScheme() {
        #expect(ChildConsentPolicyLink.from(url: URL(string: "rtr-legal://terms")!) == .termsOfService)
        #expect(ChildConsentPolicyLink.from(url: URL(string: "rtr-legal://privacy")!) == .privacyPolicy)
    }

    @Test func foreignUrlsAreLeftToTheSystem() {
        #expect(ChildConsentPolicyLink.from(url: URL(string: "https://roadtriproyale.com")!) == nil)
        #expect(ChildConsentPolicyLink.from(url: URL(string: "roadtrip-royale://family/f1")!) == nil)
        #expect(ChildConsentPolicyLink.from(url: URL(string: "rtr-legal://unknown")!) == nil)
    }

    @Test func everyLinkBuildsARoundTrippableUrl() {
        for link in ChildConsentPolicyLink.allCases {
            let url = try? #require(link.url)
            #expect(url.flatMap(ChildConsentPolicyLink.from(url:)) == link)
        }
    }

    /// The citations became links by adding markdown markup only. The RENDERED wording
    /// must stay byte-identical, because that text is consent evidence — a real wording
    /// change would require bumping CONSENT_TEXT_VERSION server-side.
    @Test func policySummaryRendersWithoutAnyVisibleMarkup() throws {
        let raw = "family.child.policy_summary".localized
        let attributed = try AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let rendered = String(attributed.characters)

        #expect(!rendered.contains("rtr-legal"))
        #expect(!rendered.contains("]("))
        #expect(!rendered.contains("["))
        #expect(rendered.contains("Terms of Service section 2"))
        #expect(rendered.contains("Privacy Policy section 12"))
        #expect(rendered == """
        Children play only inside your family. We keep their username and avatar, trip \
        activity, discoveries, and lifetime stats. No ads, no location, no search, no \
        friends. You can review or delete their data any time in Family Settings. See \
        Terms of Service section 2 and Privacy Policy section 12.
        """)
    }

    /// Both citations must actually carry a link attribute — VoiceOver needs real links,
    /// not styled text.
    @Test func bothCitationsCarryLinkAttributes() throws {
        let attributed = try AttributedString(
            markdown: "family.child.policy_summary".localized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let linked = attributed.runs.compactMap { run -> ChildConsentPolicyLink? in
            guard let url = run.link else { return nil }
            return ChildConsentPolicyLink.from(url: url)
        }
        #expect(Set(linked) == Set(ChildConsentPolicyLink.allCases))
    }
}

// MARK: - Approval declaration (FR-1 / FR-25)

struct ChildApprovalPolicyTests {

    @Test func adultTargetApprovesWithoutAnyDeclaration() {
        let draft = ChildApprovalDraft.initial(for: .notChild)
        #expect(draft.isChild == false)
        #expect(ChildApprovalPolicy.canApprove(state: .notChild, draft: draft))
        #expect(ChildApprovalPolicy.showsConsentBlock(draft: draft) == false)
    }

    @Test func declaringAChildRequiresBothAcknowledgments() {
        var draft = ChildApprovalDraft(isChild: true)
        #expect(!ChildApprovalPolicy.canApprove(state: .notChild, draft: draft))

        draft.consent.consentAcknowledged = true
        #expect(!ChildApprovalPolicy.canApprove(state: .notChild, draft: draft))

        draft.consent.guardianAffirmed = true
        #expect(ChildApprovalPolicy.canApprove(state: .notChild, draft: draft))
        #expect(ChildApprovalPolicy.showsConsentBlock(draft: draft))
    }

    @Test func stickyTargetCannotBeApprovedWithoutAnExplicitAnswer() {
        // FR-25: the server rejects a silent approval; the UI must block it first.
        let draft = ChildApprovalDraft.initial(for: .alreadyChild)
        #expect(draft.isChild == nil)
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))

        // FR-66(b): explicit "no" is the new-guardian correction, and it is no longer free.
        // It used to approve on its own; clearing a flag now costs the same evidence as
        // setting one, because a bare "no" was the middle link of the CB-7 laundering chain.
        #expect(
            !ChildApprovalPolicy.canApprove(
                state: .alreadyChild,
                draft: ChildApprovalDraft(isChild: false)
            )
        )
    }

    @Test func clearingAStickyFlagNeedsAReasonAndBothAcknowledgments() {
        var draft = ChildApprovalDraft(isChild: false)
        #expect(ChildApprovalPolicy.showsCorrectionBlock(state: .alreadyChild, draft: draft))
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))

        draft.correction.reason = .childTurned13
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))

        draft.correction.statusAcknowledged = true
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))

        draft.correction.guardianAffirmed = true
        #expect(ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))

        // A reason is not optional even with both boxes ticked.
        draft.correction.reason = nil
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))
    }

    @Test func theCorrectionBlockIsScopedToKnownFlaggedTargets() {
        // An unreadable target (FR-12 denies peer reads) must not put correction ceremony
        // in front of every ordinary adult approval. If the server disagrees it rejects,
        // and the view model re-resolves the row to `.alreadyChild` for a second pass.
        let clearing = ChildApprovalDraft(isChild: false)
        #expect(!ChildApprovalPolicy.showsCorrectionBlock(state: .unknown, draft: clearing))
        #expect(!ChildApprovalPolicy.showsCorrectionBlock(state: .notChild, draft: clearing))
        #expect(ChildApprovalPolicy.canApprove(state: .unknown, draft: clearing))

        // And it never shows on the capture branch — that is the consent block's job.
        var declaring = ChildApprovalDraft(isChild: true)
        declaring.consent = ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        #expect(!ChildApprovalPolicy.showsCorrectionBlock(state: .alreadyChild, draft: declaring))
    }

    @Test func unresolvableTargetIsTreatedLikeAStickyOne() {
        // FR-12 denies peer reads of a non-family child's doc, so "unknown" is the
        // expected state for exactly the case that matters. Never assume adult.
        #expect(ChildApprovalTargetState.unknown.requiresExplicitDeclaration)
        #expect(ChildApprovalTargetState.alreadyChild.requiresExplicitDeclaration)
        #expect(!ChildApprovalTargetState.notChild.requiresExplicitDeclaration)
        #expect(
            !ChildApprovalPolicy.canApprove(
                state: .unknown,
                draft: .initial(for: .unknown)
            )
        )
    }

    @Test func declaringAChildOnAStickyTargetStillNeedsFreshConsent() {
        var draft = ChildApprovalDraft(isChild: true)
        #expect(!ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))
        draft.consent = ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        #expect(ChildApprovalPolicy.canApprove(state: .alreadyChild, draft: draft))
    }
}

// MARK: - Callable payloads (field names + clientMetadata sibling)

struct FamilyChildStatusPayloadTests {

    @Test func setChildPayloadCarriesBothAcknowledgments() {
        let payload = FamilyChildStatusPayload.setChild(
            familyId: "fam-1",
            memberUserId: "child-1",
            consent: ChildConsentDraft(
                consentAcknowledged: true,
                guardianAffirmed: true,
                expectedAgeOutYear: 2031
            )
        )
        #expect(payload["familyId"] as? String == "fam-1")
        #expect(payload["memberId"] as? String == "child-1")
        #expect(payload["isChild"] as? Bool == true)
        #expect(payload["consentAcknowledged"] as? Bool == true)
        #expect(payload["guardianAffirmed"] as? Bool == true)
        #expect(payload["expectedAgeOutYear"] as? Int == 2031)
        #expect(payload["correctionReason"] == nil)
    }

    @Test func setChildPayloadOmitsAnUnsuppliedAgeOutYear() {
        let payload = FamilyChildStatusPayload.setChild(
            familyId: "fam-1",
            memberUserId: "child-1",
            consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        )
        #expect(payload["expectedAgeOutYear"] == nil)
    }

    @Test func clearChildPayloadIsCorrectionOnly() {
        let payload = FamilyChildStatusPayload.clearChild(
            familyId: "fam-1",
            memberUserId: "child-1",
            correctionReason: .childTurned13
        )
        #expect(payload["isChild"] as? Bool == false)
        #expect(payload["correctionReason"] as? String == "child_turned_13")
        // A clear is never a consent capture.
        #expect(payload["consentAcknowledged"] == nil)
        #expect(payload["guardianAffirmed"] == nil)
    }

    @Test func deletionAndConsentStatusPayloadsUseChildUserId() {
        let deletion = FamilyChildStatusPayload.requestChildDataDeletion(
            familyId: "fam-1",
            childUserId: "child-1"
        )
        #expect(deletion["familyId"] as? String == "fam-1")
        #expect(deletion["childUserId"] as? String == "child-1")

        let status = FamilyChildStatusPayload.parentalConsentStatus(
            familyId: "fam-1",
            childUserId: "child-1"
        )
        #expect(status["familyId"] as? String == "fam-1")
        #expect(status["childUserId"] as? String == "child-1")
    }

    @Test func approvalPayloadOmitsChildFieldsWhenUnanswered() {
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: true,
            declaration: ChildApprovalDraft(isChild: nil)
        )
        #expect(payload["response"] as? String == "approve")
        #expect(payload["isChild"] == nil)
        #expect(payload["consentAcknowledged"] == nil)
    }

    @Test func approvalPayloadSendsExplicitFalseWithoutConsentFields() {
        // An unanswered correction block sends the bare `false` — the shape the server
        // treats as a plain approval for an UNFLAGGED target, and refuses for a flagged one.
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: true,
            declaration: ChildApprovalDraft(isChild: false)
        )
        #expect(payload["isChild"] as? Bool == false)
        #expect(payload["correctionReason"] == nil)
        #expect(payload["consentAcknowledged"] == nil)
        #expect(payload["guardianAffirmed"] == nil)
    }

    /// FR-66(b): the server requires an enumerated reason plus both acknowledgments on the
    /// clear path. These field names must match the `data?.…` reads in `family.ts`.
    @Test func approvalPayloadSendsTheCorrectionEvidenceWhenClearingAFlag() {
        var declaration = ChildApprovalDraft(isChild: false)
        declaration.correction = ChildCorrectionDraft(
            reason: .flagSetInError,
            statusAcknowledged: true,
            guardianAffirmed: true
        )
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: true,
            declaration: declaration
        )
        #expect(payload["isChild"] as? Bool == false)
        #expect(payload["correctionReason"] as? String == "flag_set_in_error")
        #expect(payload["consentAcknowledged"] as? Bool == true)
        #expect(payload["guardianAffirmed"] as? Bool == true)
        // The capture-only field never rides along on a clear.
        #expect(payload["expectedAgeOutYear"] == nil)
    }

    @Test func approvalPayloadSendsConsentFieldsWithTrue() {
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: true,
            declaration: ChildApprovalDraft(
                isChild: true,
                consent: ChildConsentDraft(
                    consentAcknowledged: true,
                    guardianAffirmed: true,
                    expectedAgeOutYear: 2030
                )
            )
        )
        #expect(payload["isChild"] as? Bool == true)
        #expect(payload["consentAcknowledged"] as? Bool == true)
        #expect(payload["guardianAffirmed"] as? Bool == true)
        #expect(payload["expectedAgeOutYear"] as? Int == 2030)
    }

    @Test func declineNeverCarriesAChildDeclaration() {
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: false,
            declaration: ChildApprovalDraft(
                isChild: true,
                consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
            )
        )
        #expect(payload["response"] as? String == "decline")
        #expect(payload["isChild"] == nil)
    }

    /// client-metadata-cloud-calls rule: sibling field, never nested in the payload.
    @Test func clientMetadataRidesAsASiblingField() {
        let payload = FamilyChildStatusPayload
            .setChild(
                familyId: "fam-1",
                memberUserId: "child-1",
                consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
            )
            .addingClientMetadata()

        let metadata = payload["clientMetadata"] as? [String: Any]
        #expect(metadata != nil)
        #expect(metadata?["clientAppVersion"] != nil)
        // The gameplay fields stay top-level beside it.
        #expect(payload["familyId"] as? String == "fam-1")
        #expect(payload["isChild"] as? Bool == true)
    }

    @Test func everyChildCallablePayloadCarriesClientMetadata() {
        let payloads: [[String: Any]] = [
            FamilyChildStatusPayload.clearChild(
                familyId: "f", memberUserId: "m", correctionReason: .flagSetInError
            ),
            FamilyChildStatusPayload.requestChildDataDeletion(familyId: "f", childUserId: "c"),
            FamilyChildStatusPayload.parentalConsentStatus(familyId: "f", childUserId: "c"),
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f", requestId: "r", approve: true, declaration: nil
            )
        ]
        for payload in payloads {
            #expect(payload.addingClientMetadata()["clientMetadata"] as? [String: Any] != nil)
        }
    }
}

// MARK: - Server rejection mapping (FR-25 race)

struct FamilyChildApprovalRejectionTests {

    private func callableError(_ code: FunctionsErrorCode, _ message: String) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    @Test func recognizesTheMissingExplicitDeclarationRejection() {
        let error = callableError(
            .failedPrecondition,
            "This member is marked as a child; approval must explicitly declare isChild"
        )
        #expect(FamilyChildApprovalRejection.isMissingExplicitChildDeclaration(error))
    }

    @Test func ignoresOtherFailedPreconditions() {
        let error = callableError(.failedPrecondition, "Cannot add user to family")
        #expect(!FamilyChildApprovalRejection.isMissingExplicitChildDeclaration(error))
    }

    @Test func ignoresNonCallableErrors() {
        let error = NSError(domain: "Other", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "approval must explicitly declare isChild"
        ])
        #expect(!FamilyChildApprovalRejection.isMissingExplicitChildDeclaration(error))
    }
}

// MARK: - Consent history parsing (FR-29)

struct ParentalConsentStatusParsingTests {

    @Test func parsesCuratedRowsAndDropsUnusableOnes() {
        let status = ParentalConsentStatus.parse([
            "isChildAccount": true,
            "records": [
                [
                    "eventType": "AUDIT_PARENTAL_CONSENT_GRANTED",
                    "createdAtMillis": 1_770_000_000_000,
                    "guardianAffirmed": true,
                    "expectedAgeOutYear": 2031
                ],
                [
                    "eventType": "AUDIT_PARENTAL_CONSENT_CORRECTED",
                    "createdAtMillis": 1_770_600_000_000,
                    "reason": "child_turned_13"
                ],
                ["createdAtMillis": 1] // no eventType — dropped
            ]
        ])

        #expect(status.records.count == 2)
        #expect(status.records[0].eventType == .granted)
        #expect(status.records[0].guardianAffirmed == true)
        #expect(status.records[0].expectedAgeOutYear == 2031)
        #expect(status.records[0].createdAt != nil)
        #expect(status.records[1].eventType == .corrected)
        #expect(status.records[1].localizedCorrectionReason != nil)
    }

    @Test func unknownEventTypesSurviveWithFallbackCopy() {
        let status = ParentalConsentStatus.parse([
            "records": [["eventType": "AUDIT_SOMETHING_NEW", "createdAtMillis": NSNull()]]
        ])
        #expect(status.records.count == 1)
        #expect(status.records[0].eventType == nil)
        #expect(status.records[0].createdAt == nil)
        #expect(!status.records[0].localizedTitle.isEmpty)
    }

    @Test func unknownReasonSlugsAreNotRenderedRaw() {
        let status = ParentalConsentStatus.parse([
            "records": [[
                "eventType": "AUDIT_PARENTAL_CONSENT_REVOKED",
                "reason": "parent_removed_child"
            ]]
        ])
        #expect(status.records[0].localizedCorrectionReason == nil)
    }

    @Test func malformedResponsesDegradeToAnEmptyHistory() {
        #expect(ParentalConsentStatus.parse(nil).records.isEmpty)
        #expect(ParentalConsentStatus.parse("nope").records.isEmpty)
        #expect(ParentalConsentStatus.parse(["records": "nope"]).records.isEmpty)
    }
}

// MARK: - Manage-control gating (mirrors the server's target rules)

struct FamilyChildManagePolicyTests {

    private func canManage(
        isCaptainOrCreator: Bool = true,
        currentUserId: String? = "captain",
        memberUserId: String = "scout",
        familyCreatorId: String? = "creator",
        memberRole: FamilyMember.FamilyRole = .scout
    ) -> Bool {
        FamilyChildManagePolicy.canManageChildStatus(
            isCaptainOrCreator: isCaptainOrCreator,
            currentUserId: currentUserId,
            memberUserId: memberUserId,
            familyCreatorId: familyCreatorId,
            memberRole: memberRole
        )
    }

    @Test func managersMayManageOrdinaryMembers() {
        #expect(canManage())
    }

    @Test func nonManagersMayNot() {
        #expect(!canManage(isCaptainOrCreator: false))
    }

    @Test func selfTargetsAreRefused() {
        #expect(!canManage(memberUserId: "captain"))
    }

    @Test func creatorTargetsAreRefusedByIdAndByRole() {
        #expect(!canManage(memberUserId: "creator"))
        #expect(!canManage(memberUserId: "someone", memberRole: .creator))
    }

    @Test func signedOutViewersMayNot() {
        #expect(!canManage(currentUserId: nil))
        #expect(!canManage(currentUserId: ""))
    }
}
