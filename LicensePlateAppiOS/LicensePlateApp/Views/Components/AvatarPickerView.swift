//
//  AvatarPickerView.swift
//  LicensePlateApp
//
//  Normal horizontal scroll; fixed-size items; selected item has colored shadow highlight.
//

import SwiftUI

struct AvatarPickerView: View {
    let items: [AvatarDisplayItem]
    @Binding var selectedId: String?
    let onLockedTap: (AvatarDisplayItem, AvatarUnlockSource) -> Void
    var onSelected: (() -> Void)?
    
    private let itemSize: CGFloat = 94
    private let spacing: CGFloat = 18
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(items) { item in
                    AvatarPickerItemView(
                        item: item,
                        isSelected: selectedId == item.id,
                        itemSize: itemSize
                    )
                    .onTapGesture {
                        if item.isUnlocked {
                            selectedId = item.id
                            onSelected?()
                        } else {
                            onLockedTap(item, item.unlockSource)
                        }
                    }
                }
            }
            .padding(.horizontal, spacing)
        }
        .onAppear {
            if selectedId == nil, let first = items.first {
                selectedId = first.id
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedId: String? = "navigator_raccoon"
    
    let catalog = AvatarCatalogService.shared
    let items = catalog.displayItems(for: nil)
    
    return VStack {
        AvatarPickerView(
            items: items,
            selectedId: $selectedId,
            onLockedTap: { _, _ in },
            onSelected: nil
        )
        .frame(height: 196)
        Text("Selected: \(selectedId ?? "none")")
            .font(.caption)
    }
    .padding()
}
