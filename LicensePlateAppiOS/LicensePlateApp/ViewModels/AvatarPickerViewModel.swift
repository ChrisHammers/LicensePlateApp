//
//  AvatarPickerViewModel.swift
//  LicensePlateApp
//
//  Holds catalog + entitlement; exposes displayItems and selection; reusable for onboarding and settings.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AvatarPickerViewModel: ObservableObject {
    
    @Published var displayItems: [AvatarDisplayItem] = []
    @Published var selectedId: String?
    @Published var showUnlockSheet: Bool = false
    @Published var sheetItem: AvatarDisplayItem?
    @Published var sheetUnlockSource: AvatarUnlockSource?
    
    private let catalogService: AvatarCatalogService
    private var currentUser: AppUser?
    
    init(catalogService: AvatarCatalogService) {
        self.catalogService = catalogService
    }
    
    func setUser(_ user: AppUser?) {
        currentUser = user
        displayItems = catalogService.displayItems(for: user)
        if selectedId == nil, let id = user?.avatarId {
            selectedId = id
        }
    }
    
    func select(id: String) {
        guard let item = displayItems.first(where: { $0.id == id }), item.isUnlocked else { return }
        selectedId = id
    }
    
    func handleLockedTap(item: AvatarDisplayItem) {
        sheetItem = item
        sheetUnlockSource = item.unlockSource
        showUnlockSheet = true
    }
    
    func dismissSheet() {
        showUnlockSheet = false
        sheetItem = nil
        sheetUnlockSource = nil
    }
}
