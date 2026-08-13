//
//  AgeGateViewModel.swift
//  LicensePlateApp
//
//  COPPA F-6 (FR-27): view model for the neutral age screen. Derives the category
//  from the selected birth year, records ONLY the category + timestamp (D-3), and
//  emits shown/completed funnel analytics — never the answer (SRS §12).
//

import Foundation
import Combine

/// Where the age screen was presented from (analytics label only — never joined
/// with the answer). `launch` = quick-start's pre-play step; `onboarding` = the
/// legacy onboarding step before account creation; `registration` = a create-account
/// form's in-flow ask.
enum AgeGateSource: String {
    case launch
    case onboarding
    case registration
}

@MainActor
final class AgeGateViewModel: ObservableObject {
    @Published var selectedBirthYear: Int?

    let source: AgeGateSource
    let yearOptions: [Int]

    private let store: AgeGateStore
    private let analytics: AnalyticsLogging
    private let currentYear: Int
    private var didLogShown = false

    init(
        source: AgeGateSource,
        store: AgeGateStore = .shared,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        currentYear: Int = Calendar.current.component(.year, from: .now)
    ) {
        self.source = source
        self.store = store
        self.analytics = analytics
        self.currentYear = currentYear
        // Newest first; 102 years covers all plausible answers without implying a target.
        self.yearOptions = Array(((currentYear - 101)...currentYear).reversed())
    }

    var canContinue: Bool {
        selectedBirthYear != nil
    }

    /// Logs the funnel "shown" event once (screen-shown only — no age data, SRS §12).
    func recordShown() {
        guard !didLogShown else { return }
        didLogShown = true
        analytics.log(.ageGateShown(source: source.rawValue))
    }

    /// Derives the category, persists it (birth year is discarded), logs "completed"
    /// (never the answer), and reports success so the caller can continue routing.
    func submit() -> Bool {
        guard let birthYear = selectedBirthYear else { return false }
        let category = AgeGateStore.category(forBirthYear: birthYear, currentYear: currentYear)
        store.recordAnswer(category)
        // COPPA F-9 (FR-46): this answer IS the age resolution. Re-run the one
        // apply-postures routine so the deferred SDK startups are re-evaluated now,
        // rather than waiting for the next identity transition — the flows that answer
        // without immediately provisioning a uid would otherwise stay held. Idempotent,
        // so the provisioning transition that usually follows costs nothing.
        ChildSessionPostureCoordinator.shared.applyPostures(trigger: .ageResolution)
        analytics.log(.ageGateCompleted(source: source.rawValue))
        return true
    }
}
