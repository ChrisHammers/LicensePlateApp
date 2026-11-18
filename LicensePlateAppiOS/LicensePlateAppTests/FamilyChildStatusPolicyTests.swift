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

    // Owner ruling 2026-08-28 (manager_set → email_plus): flagging an EXISTING member
    // additionally requires the turns-13 attestation — the only age-out source for
    // someone who never passed the age gate. The approve flow keeps plain `isComplete`.
    @Test func memberFlagAdditionallyRequiresTheAttestation() {
        let boxesOnly = ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        #expect(boxesOnly.isComplete == true)
        #expect(boxesOnly.isCompleteForMemberFlag == false)

        var withAttestation = boxesOnly
        withAttestation.expectedAgeOutYearMonth = 203107
        #expect(withAttestation.isCompleteForMemberFlag == true)

        var attestationOnly = ChildConsentDraft()
        attestationOnly.expectedAgeOutYearMonth = 203107
        #expect(attestationOnly.isCompleteForMemberFlag == false)
    }

    @Test func expectedAgeOutYearWindowMatchesTheServer() {
        // `validateExpectedAgeOutYearMonth` (owner ruling 2026-08-27: full month + year
        // as one YYYYMM integer): month 1–12, year nowYear ... nowYear + 13.
        #expect(ExpectedAgeOutYearOptions.isValid(nil, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.isValid(202601, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.isValid(203912, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(202506, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(204001, currentYear: 2026))
        // Month bounds — and a bare year (the superseded shape) no longer validates.
        #expect(!ExpectedAgeOutYearOptions.isValid(202600, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(202613, currentYear: 2026))
        #expect(!ExpectedAgeOutYearOptions.isValid(2031, currentYear: 2026))
        #expect(ExpectedAgeOutYearOptions.options(currentYear: 2026).count == 14)
        // The two-picker composition round-trips.
        #expect(ExpectedAgeOutYearOptions.compose(month: 3, year: 2031) == 203103)
        #expect(ExpectedAgeOutYearOptions.compose(month: nil, year: 2031) == nil)
        #expect(ExpectedAgeOutYearOptions.compose(month: 3, year: nil) == nil)
        #expect(ExpectedAgeOutYearOptions.month(of: 203103) == 3)
        #expect(ExpectedAgeOutYearOptions.year(of: 203103) == 2031)
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

    /// F-21: the deleted policy summary's two citations moved into the full-policy links
    /// line. Read from the English bundle explicitly so the exact rendered wording is
    /// pinned regardless of the simulator's language.
    private func fullPolicyLinksMarkdown() throws -> String {
        try ConsentTextBundles.value(
            for: ConsentScopeCardPolicy.fullPolicyLinksKey,
            language: "en"
        )
    }

    @Test func fullPolicyLinksRenderWithoutAnyVisibleMarkup() throws {
        let attributed = try AttributedString(
            markdown: try fullPolicyLinksMarkdown(),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let rendered = String(attributed.characters)

        #expect(!rendered.contains("rtr-legal"))
        #expect(!rendered.contains("]("))
        #expect(!rendered.contains("["))
        #expect(rendered.contains("Terms of Service section 2"))
        #expect(rendered.contains("Privacy Policy section 12"))
        #expect(rendered == "Full details: Terms of Service section 2 and Privacy Policy section 12.")
    }

    /// Both citations must actually carry a link attribute, in every language — VoiceOver
    /// needs real links, not styled text, and the block's handler resolves exactly these.
    @Test func bothCitationsCarryLinkAttributesInEveryLanguage() throws {
        for language in ConsentTextBundles.languages {
            let attributed = try AttributedString(
                markdown: try ConsentTextBundles.value(
                    for: ConsentScopeCardPolicy.fullPolicyLinksKey,
                    language: language
                ),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            let linked = attributed.runs.compactMap { run -> ChildConsentPolicyLink? in
                guard let url = run.link else { return nil }
                return ChildConsentPolicyLink.from(url: url)
            }
            #expect(linked.count == 2, "\(language)")
            #expect(Set(linked) == Set(ChildConsentPolicyLink.allCases), "\(language)")
        }
    }

    /// The scope cards' anchors are a separate type, so this one keeps meaning exactly the
    /// two cited documents.
    @Test func policyLinkCasesStayTermsAndPrivacy() {
        #expect(ChildConsentPolicyLink.allCases == [.termsOfService, .privacyPolicy])
        for anchor in ConsentScopePolicyAnchor.allCases {
            let url = try? #require(anchor.url)
            #expect(url.flatMap(ChildConsentPolicyLink.from(url:)) == nil)
            #expect(url.flatMap(ConsentScopePolicyAnchor.from(url:)) == anchor)
        }
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
                expectedAgeOutYearMonth: 2031
            )
        )
        #expect(payload["familyId"] as? String == "fam-1")
        #expect(payload["memberId"] as? String == "child-1")
        #expect(payload["isChild"] as? Bool == true)
        #expect(payload["consentAcknowledged"] as? Bool == true)
        #expect(payload["guardianAffirmed"] as? Bool == true)
        #expect(payload["expectedAgeOutYearMonth"] as? Int == 2031)
        #expect(payload["correctionReason"] == nil)
    }

    @Test func setChildPayloadOmitsAnUnsuppliedAgeOutYear() {
        let payload = FamilyChildStatusPayload.setChild(
            familyId: "fam-1",
            memberUserId: "child-1",
            consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        )
        #expect(payload["expectedAgeOutYearMonth"] == nil)
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
        #expect(payload["expectedAgeOutYearMonth"] == nil)
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
                    expectedAgeOutYearMonth: 2030
                )
            )
        )
        #expect(payload["isChild"] as? Bool == true)
        #expect(payload["consentAcknowledged"] as? Bool == true)
        #expect(payload["guardianAffirmed"] as? Bool == true)
        #expect(payload["expectedAgeOutYearMonth"] as? Int == 2030)
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

    // MARK: F-21 (FR-65): scope selection + consent-text version

    @Test func setChildPayloadCarriesTheLaunchScopesAndTheConsentTextVersion() {
        let payload = FamilyChildStatusPayload.setChild(
            familyId: "fam-1",
            memberUserId: "child-1",
            consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
        )
        #expect(payload["consentScopes"] as? [String] == ["core"])
        #expect(payload["consentTextVersion"] as? String == "2026-11-17.consent-scopes")
        #expect(payload["consentTextVersion"] as? String == ConsentScopeCatalog.consentTextVersion)
    }

    @Test func childApprovalPayloadCarriesTheLaunchScopesAndTheConsentTextVersion() {
        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: "fam-1",
            requestId: "req-1",
            approve: true,
            declaration: ChildApprovalDraft(
                isChild: true,
                consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
            )
        )
        #expect(payload["isChild"] as? Bool == true)
        #expect(payload["consentScopes"] as? [String] == ["core"])
        #expect(payload["consentTextVersion"] as? String == ConsentScopeCatalog.consentTextVersion)
    }

    @Test func clearAndAdultPayloadsCarryNoScopeFields() {
        var correction = ChildApprovalDraft(isChild: false)
        correction.correction = ChildCorrectionDraft(
            reason: .childTurned13,
            statusAcknowledged: true,
            guardianAffirmed: true
        )
        let payloads: [[String: Any]] = [
            // setFamilyMemberChildStatus(isChild: false)
            FamilyChildStatusPayload.clearChild(
                familyId: "f", memberUserId: "m", correctionReason: .flagSetInError
            ),
            // Adult approvals: unanswered, plain false, and a completed correction.
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f", requestId: "r", approve: true, declaration: nil
            ),
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f", requestId: "r", approve: true, declaration: ChildApprovalDraft(isChild: false)
            ),
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f", requestId: "r", approve: true, declaration: correction
            ),
            // A decline never carries a declaration at all.
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f",
                requestId: "r",
                approve: false,
                declaration: ChildApprovalDraft(
                    isChild: true,
                    consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
                )
            )
        ]
        for payload in payloads {
            #expect(payload["consentScopes"] == nil)
            #expect(payload["consentTextVersion"] == nil)
        }
    }

    /// The scope fields ride top-level beside `clientMetadata`, never inside it, and the
    /// metadata never swallows them.
    @Test func scopeFieldsStayTopLevelBesideClientMetadata() {
        let childPayloads: [[String: Any]] = [
            FamilyChildStatusPayload.setChild(
                familyId: "f",
                memberUserId: "m",
                consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
            ),
            FamilyChildStatusPayload.respondToPendingRequest(
                familyId: "f",
                requestId: "r",
                approve: true,
                declaration: ChildApprovalDraft(
                    isChild: true,
                    consent: ChildConsentDraft(consentAcknowledged: true, guardianAffirmed: true)
                )
            )
        ]
        for payload in childPayloads {
            let sent = payload.addingClientMetadata()
            #expect(sent["consentScopes"] as? [String] == ["core"])
            #expect(sent["consentTextVersion"] as? String == ConsentScopeCatalog.consentTextVersion)
            let metadata = sent["clientMetadata"] as? [String: Any]
            #expect(metadata != nil)
            #expect(metadata?["consentScopes"] == nil)
            #expect(metadata?["consentTextVersion"] == nil)
            #expect(payload["clientMetadata"] == nil)
        }
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

@MainActor
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

    // MARK: F-21 (FR-65): consent-scope rejections read details.reason

    private func reasonError(
        _ reason: String,
        code: FunctionsErrorCode = .failedPrecondition,
        domain: String = FunctionsErrorDomain
    ) -> NSError {
        NSError(
            domain: domain,
            code: code.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "server English message",
                FunctionsErrorDetailsKey: ["reason": reason]
            ]
        )
    }

    @Test func consentTextOutdatedRequiresAnAppUpdate() {
        let error = reasonError("consent_text_outdated")
        #expect(FamilyChildApprovalRejection.isConsentTextOutdated(error))
        #expect(!FamilyChildApprovalRejection.isConsentScopesInvalid(error))
        #expect(FamilyChildApprovalRejection.requiresAppUpdate(error))
    }

    @Test func consentScopesInvalidRequiresAnAppUpdate() {
        let error = reasonError("consent_scopes_invalid")
        #expect(FamilyChildApprovalRejection.isConsentScopesInvalid(error))
        #expect(!FamilyChildApprovalRejection.isConsentTextOutdated(error))
        #expect(FamilyChildApprovalRejection.requiresAppUpdate(error))
    }

    @Test func otherReasonsCodesAndDomainsAreNotAnAppUpdate() {
        #expect(!FamilyChildApprovalRejection.requiresAppUpdate(reasonError("unconsented_child")))
        #expect(!FamilyChildApprovalRejection.requiresAppUpdate(
            reasonError("consent_text_outdated", code: .invalidArgument)
        ))
        #expect(!FamilyChildApprovalRejection.requiresAppUpdate(
            reasonError("consent_text_outdated", domain: "Other")
        ))
        // No details at all: the message alone never counts.
        #expect(!FamilyChildApprovalRejection.requiresAppUpdate(
            callableError(.failedPrecondition, "consent_text_outdated")
        ))
    }

    /// Both callables' error surfaces show the one update line. The Mark-as-a-child path
    /// goes through the repository's mapping; the approve path's view model uses the key.
    @Test func bothReasonsMapToTheUpdateRequiredLine() {
        #expect(FamilyChildApprovalRejection.updateRequiredMessageKey == "family.consent_scope.update_required")
        for reason in ["consent_text_outdated", "consent_scopes_invalid"] {
            let mapped = FamilyRepository.childStatusCallableError(reasonError(reason)) as NSError
            #expect(
                mapped.localizedDescription
                    == FamilyChildApprovalRejection.updateRequiredMessageKey.localized
            )
            #expect(mapped.localizedDescription != FamilyChildApprovalRejection.updateRequiredMessageKey)
        }
        // Any other failed-precondition keeps the generic line.
        let other = FamilyRepository.childStatusCallableError(reasonError("unconsented_child")) as NSError
        #expect(other.localizedDescription == "family.child.error.not_allowed".localized)
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
                    "expectedAgeOutYearMonth": 2031
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
        #expect(status.records[0].expectedAgeOutYearMonth == 2031)
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
