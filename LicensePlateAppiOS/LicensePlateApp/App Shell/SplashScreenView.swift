//
//  SplashScreenView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 12/3/25.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.Theme.primaryBlue
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "car.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                    .accessibleDecorative()
                
                Text("RoadTrip Royale".localized)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .accessibleHeader("RoadTrip Royale".localized)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .accessibilityLabel("splash.loading.accessibility".localized)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("splash.loading.accessibility".localized)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    SplashScreenView()
}
