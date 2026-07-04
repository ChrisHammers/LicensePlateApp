//
//  FinderPinBadge.swift
//  LicensePlateApp
//
//  GPS Step 5.5 — where-found pin badge showing WHO found a plate.
//  Three tiers: finder avatar → initial-letter disc → generic map pin.
//  SwiftUI view for the Apple Maps path; UIImage renderer for GMSMarker icons.
//

import SwiftUI
import UIKit

enum FinderPinBadge {

    static let defaultSize: CGFloat = 32

    /// First grapheme of a display name, uppercased, for the letter-disc fallback.
    static func initial(from displayName: String?) -> String? {
        guard let first = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    /// GMSMarker icon: circle-clipped avatar, else letter disc, else nil (caller uses its generic pin).
    static func markerIcon(avatarImage: UIImage?, displayName: String?, size: CGFloat = defaultSize) -> UIImage? {
        if let avatarImage {
            return circularIcon(size: size) { context, rect in
                context.cgContext.saveGState()
                context.cgContext.addEllipse(in: rect)
                context.cgContext.clip()
                avatarImage.draw(in: rect)
                context.cgContext.restoreGState()
            }
        }
        if let letter = initial(from: displayName) {
            return circularIcon(size: size) { context, rect in
                context.cgContext.setFillColor(UIColor(Color.Theme.primaryBlue).cgColor)
                context.cgContext.fillEllipse(in: rect)
                let font = UIFont.systemFont(ofSize: size * 0.5, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                let textSize = letter.size(withAttributes: attributes)
                letter.draw(
                    at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                    withAttributes: attributes
                )
            }
        }
        return nil
    }

    private static func circularIcon(size: CGFloat, content: (UIGraphicsImageRendererContext, CGRect) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            content(context, rect)
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
            context.cgContext.strokePath()
        }
    }
}

/// Apple Maps annotation content for a where-found pin.
struct FinderPinBadgeView: View {
    let avatarImage: UIImage?
    let displayName: String?

    var body: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: FinderPinBadge.defaultSize, height: FinderPinBadge.defaultSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
            } else if let letter = FinderPinBadge.initial(from: displayName) {
                Circle()
                    .fill(Color.Theme.primaryBlue)
                    .frame(width: FinderPinBadge.defaultSize, height: FinderPinBadge.defaultSize)
                    .overlay(
                        Text(letter)
                            .font(.system(size: FinderPinBadge.defaultSize * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                    )
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
            } else {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.Theme.accentYellow)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
    }
}

#Preview("Badge tiers") {
    HStack(spacing: 16) {
        FinderPinBadgeView(avatarImage: AvatarCatalog.image(forAvatarId: "raccoon"), displayName: "Preview Driver")
        FinderPinBadgeView(avatarImage: nil, displayName: "Sarah")
        FinderPinBadgeView(avatarImage: nil, displayName: nil)
    }
    .padding()
}
