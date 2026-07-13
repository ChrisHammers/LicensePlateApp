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
    
    private var catalogImage: UIImage? {
        guard let avatarId = user.avatarId,
              let item = AvatarCatalog.avatar(byId: avatarId),
              item.assetSource == .bundled else {
            return nil
        }
        return UIImage(named: item.assetName)
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else if let catalogImage {
                Image(uiImage: catalogImage)
                    .resizable()
                    .scaledToFill()
            } else {
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
        guard let imageURL = user.userImageURL, !imageURL.isEmpty else {
            loadedImage = nil
            return
        }
        
        if let cachedData = UserImageCache.shared.loadImage(for: user.id) {
            if let image = UIImage(data: cachedData) {
                loadedImage = image
                return
            }
        }
        
        isLoading = true
        loadError = nil
        
        do {
            let storageService = FirebaseStorageService()
            let imageData = try await storageService.downloadUserImage(userId: user.id)
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
        UserImageView(user: AppUser(userName: "TestUser", avatarId: "navigator_raccoon"), size: 100)
        UserImageView(user: AppUser(userName: "TestUser2", avatarId: "scout_otter"), size: 150)
    }
    .padding()
}
