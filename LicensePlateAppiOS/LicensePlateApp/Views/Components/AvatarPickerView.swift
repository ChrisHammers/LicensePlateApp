//
//  AvatarPickerView.swift
//  LicensePlateApp
//
//  Horizontal center-snapping avatar picker; scale by distance; locked tap callback.
//

import SwiftUI

struct AvatarPickerView: View {
    let items: [AvatarDisplayItem]
    @Binding var selectedId: String?
    let onLockedTap: (AvatarDisplayItem, AvatarUnlockSource) -> Void
    var onSelected: (() -> Void)?
    
    private let itemWidth: CGFloat = 96
    private let centerScale: CGFloat = 1.0
    private let sideScale: CGFloat = 0.78
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        AvatarPickerItemView(
                            item: item,
                            isSelected: selectedId == item.id,
                            scale: selectedId == item.id ? centerScale : sideScale,
                            itemSize: itemWidth
                        )
                        .id(item.id)
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
                .scrollTargetLayout()
                .padding(.horizontal, itemWidth)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedId, anchor: .center)
            .onAppear {
                if let id = selectedId {
                    proxy.scrollTo(id, anchor: .center)
                } else if let first = items.first {
                    selectedId = first.id
                }
            }
            .onChange(of: selectedId) { _, newId in
                if let id = newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
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
        .frame(height: 140)
        Text("Selected: \(selectedId ?? "none")")
            .font(.caption)
    }
    .padding()
}
