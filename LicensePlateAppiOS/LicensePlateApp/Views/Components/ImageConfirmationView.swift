//
//  ImageConfirmationView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct ImageConfirmationView: View {
    let image: UIImage?
    let onUse: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Preview Image
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        // Cancel Button
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.Theme.primaryBlue, lineWidth: 2)
                                )
                        }
                        
                        // Use Button
                        Button {
                            onUse()
                        } label: {
                            Text("Use Photo")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.Theme.primaryBlue)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Preview Photo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ImageConfirmationView(
        image: UIImage(systemName: "photo"),
        onUse: {
            print("Use photo")
        },
        onCancel: {
            print("Cancel")
        }
    )
}

