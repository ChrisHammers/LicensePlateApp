//
//  AppBackgroundView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

/// A view wrapper that applies the appropriate background based on user preferences
struct AppBackgroundView<Content: View>: View {
    @AppStorage("appBackgroundStyle") private var backgroundStyleRaw: String = AppBackgroundStyle.none.rawValue
    @AppStorage("appDarkMode") private var darkModeRaw: String = AppDarkMode.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    private var backgroundStyle: AppBackgroundStyle {
        AppBackgroundStyle(rawValue: backgroundStyleRaw) ?? .none
    }
    
    private var effectiveColorScheme: ColorScheme? {
        AppPreferences.colorSchemeFromPreference(rawValue: darkModeRaw)
    }
    
    var body: some View {
        ZStack {
            if let imageName = AppPreferences.backgroundImageName(
                style: backgroundStyle,
                colorScheme: effectiveColorScheme ?? systemColorScheme
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

