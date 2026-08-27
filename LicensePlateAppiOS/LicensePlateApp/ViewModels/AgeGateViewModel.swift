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
    /// FR-55 (v3.7): birth MONTH joins the year for exact-boundary classification.
    /// Same neutrality rules as the year: no default selection, nothing signals a cutoff.
    @Published var selectedBirthMonth: Int?

    let source: AgeGateSource
    let yearOptions: [Int]
    let monthOptions = Array(1...12)

    private let store: AgeGateStore
    private let analytics: AnalyticsLogging
    private let currentYear: Int
    private let currentMonth: Int
    private var didLogShown = false

    init(
        source: AgeGateSource,
        store: AgeGateStore = .shared,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        currentYear: Int = Calendar.current.component(.year, from: .now),
        currentMonth: Int = Calendar.current.component(.month, from: .now)
    ) {
        self.source = source
        self.store = store
        self.analytics = analytics
        self.currentYear = currentYear
        self.currentMonth = currentMonth
        // Newest first; 102 years covers all plausible answers without implying a target.
        self.yearOptions = Array(((currentYear - 101)...currentYear).reversed())
    }

    var canContinue: Bool {
        selectedBirthYear != nil && selectedBirthMonth != nil
    }

    /// Localized month name for the picker, in the app's selected language — the
    /// formatter's symbols, so no per-month strings ship in the three catalogs.
    func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: LocalizationHelper.currentAppLanguage.localeCode)
        let symbols = formatter.standaloneMonthSymbols ?? formatter.monthSymbols ?? []
        guard month >= 1, month <= symbols.count else { return String(month) }
        return symbols[month - 1]
    }

    /// Logs the funnel "shown" event once (screen-shown only — no age data, SRS §12).
    func recordShown() {
        guard !didLogShown else { return }
        didLogShown = true
        analytics.log(.ageGateShown(source: source.rawValue))
    }

    /// Derives the category, persists it (birth month and year are discarded — only the
    /// category, timestamp, and, for an under-13 answer, the FR-110 age-out marker
    /// survive), logs "completed" (never the answer), and reports success so the caller
    /// can continue routing.
    func submit() -> Bool {
        guard let birthYear = selectedBirthYear, let birthMonth = selectedBirthMonth else {
            return false
        }
        let category = AgeGateStore.category(
            forBirthMonth: birthMonth,
            birthYear: birthYear,
            currentMonth: currentMonth,
            currentYear: currentYear
        )
        // FR-110(a): the marker is computed here — the one moment the inputs exist —
        // and only an under-13 answer persists it (recordAnswer ignores it otherwise).
        store.recordAnswer(
            category,
            ageOutYearMonth: category == .under13
                ? AgeGateStore.ageOutYearMonth(forBirthMonth: birthMonth, birthYear: birthYear)
                : nil
        )
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
