//
//  UserImageView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct UserImageView: View {
    let user: AppUser
    let size: CGFloat
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: Error?
    
    init(user: AppUser, size: CGFloat = 100) {
        self.user = user
        self.size = size
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else if let defaultImage = UIImage(named: user.defaultImageName) {
                Image(uiImage: defaultImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback to system icon if asset not found
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.Theme.primaryBlue.opacity(0.3), lineWidth: 2)
        )
        .overlay {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .task {
            await loadUserImage()
        }
        .onChange(of: user.userImageURL) { oldValue, newValue in
            if oldValue != newValue {
                Task {
                    await loadUserImage()
                }
            }
        }
    }
    
    private func loadUserImage() async {
        // If no custom image URL, use default asset
        guard let imageURL = user.userImageURL, !imageURL.isEmpty else {
            loadedImage = nil
            return
        }
        
        // Check cache first
        if let cachedData = UserImageCache.shared.loadImage(for: user.id) {
            if let image = UIImage(data: cachedData) {
                loadedImage = image
                return
            }
        }
        
        // Load from Firebase Storage
        isLoading = true
        loadError = nil
        
        do {
            let storageService = FirebaseStorageService()
            let imageData = try await storageService.downloadUserImage(userId: user.id)
            
            // Cache the image
            UserImageCache.shared.saveImage(imageData, for: user.id)
            
            if let image = UIImage(data: imageData) {
                await MainActor.run {
                    loadedImage = image
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                loadError = error
                isLoading = false
                print("⚠️ Failed to load user image: \(error)")
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UserImageView(user: AppUser(userName: "TestUser",  avatarColor: .orange, avatarType: .dog), size: 100)
        UserImageView(user: AppUser(userName: "TestUser2", avatarColor: .blue, avatarType: .cat), size: 150)
    }
    .padding()
}

