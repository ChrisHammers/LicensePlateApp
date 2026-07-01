//
//  OnboardingBackgroundView.swift
//  LicensePlateApp
//
//  Fixed paths-style background used by onboarding and deferred profile setup steps.
//

import SwiftUI

struct OnboardingBackgroundView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            if let imageName = AppPreferences.backgroundImageName(
                style: .paths,
                colorScheme: colorScheme
            ) {
                Image(imageName)
                    .resizable()
                    .ignoresSafeArea()
            } else {
                Color.Theme.background
                    .ignoresSafeArea()
            }

            content
        }
    }
}
