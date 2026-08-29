//
//  FamilyChildPrivacyViewModel.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-29 → FR-61): state for the "Child privacy" review surface.
//
//  FR-61 supersedes FR-29's static category list: the held-data section renders the
//  LIVE inventory from the guardianship-gated `getChildDataInventory` callable, with a
//  share-sheet export. Consent history stays the second half. Either load failing
//  degrades to an explanatory row — the parent's review right is never blocked on the
//  other half.
//

import Foundation
import Combine

@MainActor
final class FamilyChildPrivacyViewModel: ObservableObject {
    enum HistoryState: Equatable {
        case idle
        case loading
        case loaded([ParentalConsentRecord])
        case unavailable
    }

    enum InventoryState: Equatable {
        case idle
        case loading
        case loaded(ChildDataInventory)
        case unavailable
    }

    @Published private(set) var historyState: HistoryState = .idle
    @Published private(set) var inventoryState: InventoryState = .idle
    /// FR-61 export: a real temp FILE (so the share sheet shows a sensible default
    /// name) written once both halves settle; nil until the inventory loads.
    @Published private(set) var exportFileURL: URL?

    private let loadConsentHistory: (String) async throws -> ParentalConsentStatus
    private let loadInventory: (String) async throws -> ChildDataInventory?

    init(
        loadConsentHistory: @escaping (String) async throws -> ParentalConsentStatus,
        loadInventory: @escaping (String) async throws -> ChildDataInventory?
    ) {
        self.loadConsentHistory = loadConsentHistory
        self.loadInventory = loadInventory
    }

    func load(childUserId: String, displayName: String) async {
        guard historyState == .idle, inventoryState == .idle else { return }
        historyState = .loading
        inventoryState = .loading

        async let history: Void = loadHistory(childUserId: childUserId)
        async let inventory: Void = loadLiveInventory(childUserId: childUserId)
        _ = await (history, inventory)

        buildExportFile(displayName: displayName)
    }

    /// Owner finding 2026-08-29: a process-level callable wedge (Bug B class) shows as
    /// "unavailable" with reinstall as the only visible way out — give the row a real
    /// retry instead. Resets both halves and reloads.
    func retry(childUserId: String, displayName: String) async {
        historyState = .idle
        inventoryState = .idle
        exportFileURL = nil
        await load(childUserId: childUserId, displayName: displayName)
    }

    private func loadHistory(childUserId: String) async {
        do {
            let status = try await loadConsentHistory(childUserId)
            historyState = .loaded(status.records)
        } catch {
            historyState = .unavailable
        }
    }

    private func loadLiveInventory(childUserId: String) async {
        do {
            if let inventory = try await loadInventory(childUserId) {
                inventoryState = .loaded(inventory)
            } else {
                inventoryState = .unavailable
            }
        } catch {
            inventoryState = .unavailable
        }
    }

    /// Newest first — the current consent state is what a parent looks for.
    var recordsNewestFirst: [ParentalConsentRecord] {
        guard case .loaded(let records) = historyState else { return [] }
        return records.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    var loadedInventory: ChildDataInventory? {
        guard case .loaded(let inventory) = inventoryState else { return nil }
        return inventory
    }

    /// FR-61 export: available once the inventory loaded (parent-initiated share, so
    /// FR-79's child share-gating does not apply).
    func exportText(childDisplayName: String) -> String? {
        guard let inventory = loadedInventory else { return nil }
        return ChildDataInventoryExportBuilder.text(
            childDisplayName: childDisplayName,
            inventory: inventory,
            consentRecords: recordsNewestFirst
        )
    }

    /// Owner finding 2026-08-29: the share sheet should carry a default file name.
    /// Writes the export as a named .txt in the temp directory; a write failure just
    /// leaves `exportFileURL` nil and the toolbar falls back to sharing raw text.
    private func buildExportFile(displayName: String) {
        guard let text = exportText(childDisplayName: displayName) else {
            exportFileURL = nil
            return
        }
        let fileName = ChildDataInventoryExportBuilder.exportFileName(
            childDisplayName: displayName
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportFileURL = url
        } catch {
            exportFileURL = nil
        }
    }
}

/// Pure, testable builder for the readable export. Every label goes through the same
/// localization keys the screen renders, so the shared file can never say something the
/// parent did not see.
enum ChildDataInventoryExportBuilder {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func line(_ key: String, _ value: String) -> String {
        "\(key.localized): \(value)"
    }

    /// Localized default file name for the share sheet ("<name> privacy summary.txt"),
    /// with path-hostile characters stripped from the display name.
    static func exportFileName(childDisplayName: String) -> String {
        let safeName = childDisplayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "family.child.inventory.export_filename".localized(safeName)
    }

    private static func yesNo(_ value: Bool) -> String {
        (value ? "family.child.inventory.value_yes" : "family.child.inventory.value_no").localized
    }

    static func text(
        childDisplayName: String,
        inventory: ChildDataInventory,
        consentRecords: [ParentalConsentRecord]
    ) -> String {
        var lines: [String] = []
        lines.append("family.child.inventory.export_title".localized(childDisplayName))
        if let generatedAt = inventory.generatedAt {
            lines.append(line("family.child.inventory.generated_at", dateFormatter.string(from: generatedAt)))
        }
        lines.append("")

        if let profile = inventory.profile {
            lines.append("family.child.inventory.profile_title".localized)
            lines.append(line("family.child.inventory.username", profile.userName ?? "—"))
            lines.append(line("family.child.inventory.avatar", profile.avatarId ?? "—"))
            if let ageOut = profile.ageOutYearMonth {
                lines.append(line("family.child.inventory.age_out", String(ageOut)))
            }
            lines.append("")
        }

        lines.append("family.child.inventory.identifiers_title".localized)
        let privateData = inventory.privateData ?? ChildDataInventory.PrivateData()
        lines.append(line("family.child.inventory.has_email", yesNo(privateData.hasEmail)))
        lines.append(line("family.child.inventory.has_phone", yesNo(privateData.hasPhoneNumber)))
        lines.append(line("family.child.inventory.push_token", yesNo(privateData.pushTokenPresent)))
        lines.append(
            line(
                "family.child.inventory.searchable",
                yesNo(inventory.searchIndexes?.anyIndexed ?? false)
            )
        )
        lines.append("")

        lines.append("family.child.inventory.gameplay_title".localized)
        let gameplay = inventory.gameplay ?? ChildDataInventory.Gameplay()
        lines.append(line("family.child.inventory.trip_count", String(gameplay.sessionCount)))
        lines.append(line("family.child.inventory.event_count", String(gameplay.authoredEventTotal)))
        lines.append(
            line("family.child.inventory.location_payloads", yesNo(gameplay.anyLocationPayloadExists))
        )
        for trip in gameplay.trips {
            let name = trip.tripName ?? "family.child.inventory.unnamed_trip".localized
            let events = trip.authoredEventCountsByKind.values.reduce(0, +)
            lines.append("• \(name) — \("family.child.inventory.trip_events".localized(String(events)))")
        }
        if gameplay.truncated {
            lines.append("family.child.inventory.trips_truncated".localized)
        }
        lines.append("")

        lines.append("family.child.inventory.progress_title".localized)
        lines.append(line("family.child.inventory.total_xp", String(inventory.totalXp ?? 0)))
        lines.append(line("family.child.inventory.achievements", String(inventory.achievementCount)))
        lines.append(line("family.child.inventory.friend_links", String(inventory.friendEdgeCount)))
        lines.append("")

        lines.append("family.child.inventory.vendors_title".localized)
        lines.append("family.child.inventory.vendor_revenuecat".localized)
        lines.append("family.child.inventory.vendor_analytics".localized)
        lines.append("")

        if !consentRecords.isEmpty {
            lines.append("family.child.privacy_consent_title".localized)
            for record in consentRecords {
                let date = record.createdAt.map { dateFormatter.string(from: $0) } ?? "—"
                lines.append("• \(record.localizedTitle) — \(date)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
