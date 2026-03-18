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
            // Background color matching app theme
            Color.Theme.primaryBlue
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // App logo/icon placeholder - replace with actual logo if available
                Image(systemName: "car.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                
                // App name
                Text("RoadTrip Royale")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    SplashScreenView()
}

