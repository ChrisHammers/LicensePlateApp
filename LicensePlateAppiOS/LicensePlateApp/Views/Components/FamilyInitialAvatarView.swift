//
//  FamilyInitialAvatarView.swift
//  LicensePlateApp
//
//  Family mark: circle with a giant first letter of the family name.
//

import SwiftUI

struct FamilyInitialAvatarView: View {
    let familyName: String
    var size: CGFloat = 50

    private var initial: String {
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
            Text(initial)
                .font(.system(size: size * 0.68, weight: .bold, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum FamilyDisplayFormatting {
    /// `"Hammers" Family`
    static func quotedFamilyTitle(_ name: String) -> String {
        "\"%@\" Family".localized(name)
    }

    /// You've been invited to join the "Hammers" Family.
    static func invitedToJoinSentence(_ name: String) -> String {
        "You've been invited to join the \"%@\" Family.".localized(name)
    }
}

#Preview {
    HStack(spacing: 16) {
        FamilyInitialAvatarView(familyName: "Hammers", size: 50)
        FamilyInitialAvatarView(familyName: "roadtrippers", size: 72)
        FamilyInitialAvatarView(familyName: "", size: 40)
    }
    .padding()
}
