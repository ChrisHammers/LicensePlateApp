//
//  AvatarPickerView.swift
//  LicensePlateApp
//
//  Center-snapping horizontal carousel; selected item has colored shadow highlight.
//

import SwiftUI

struct AvatarPickerView: View {
    let items: [AvatarDisplayItem]
    @Binding var selectedId: String?
    let onLockedTap: (AvatarDisplayItem, AvatarUnlockSource) -> Void
    var onSelected: (() -> Void)?
    
    private let itemSize: CGFloat = 94
    private let itemWidth: CGFloat = 116
    private let spacing: CGFloat = 18
    @State private var centeredId: String?
    
    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = max(0, (proxy.size.width - itemWidth) / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(items) { item in
                        AvatarPickerItemView(
                            item: item,
                            isSelected: selectedId == item.id,
                            itemSize: itemSize,
                            itemWidth: itemWidth
                        )
                        .id(item.id)
                        .onTapGesture {
                            centerAvatar(id: item.id, animated: true)
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
            }
            .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredId, anchor: .center)
            .onAppear {
                centerSelectedAvatar(animated: false)
            }
            .onChange(of: selectedId) { _, _ in
                centerSelectedAvatar(animated: true)
            }
            .onChange(of: items) { _, _ in
                centerSelectedAvatar(animated: false)
            }
        }
    }

    private func centerSelectedAvatar(animated: Bool) {
        let targetId = items.contains(where: { $0.id == selectedId }) ? selectedId : (centeredId ?? items.first?.id)
        centerAvatar(id: targetId, animated: animated)
    }

    private func centerAvatar(id: String?, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(.snappy) {
                centeredId = id
            }
        } else {
            centeredId = id
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
