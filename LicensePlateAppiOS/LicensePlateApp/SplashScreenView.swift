//
//  SplashScreenView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 12/3/25.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    @AppStorage("tilePreRenderProgress") private var preRenderProgress: Double = 0.0
    
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
                
                // Progress indicator with percentage
                VStack(spacing: 12) {
                    if preRenderProgress > 0 && preRenderProgress < 1.0 {
                        // Show progress bar and percentage when pre-rendering
                        VStack(spacing: 8) {
                            ProgressView(value: preRenderProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                .frame(width: 200)
                            
                            Text("Loading map tiles: \(Int(preRenderProgress * 100))%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        // Show spinner when not pre-rendering or when complete
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                }
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

