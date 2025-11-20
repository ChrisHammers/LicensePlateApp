//
//  FirebaseStorageService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import FirebaseStorage
import UIKit
import FirebaseCore

/// Service for uploading and downloading user images from Firebase Storage
class FirebaseStorageService {
    private let storage = Storage.storage()
    
    /// Upload user image to Firebase Storage
    func uploadUserImage(userId: String, imageData: Data) async throws -> String {
        let imageRef = storage.reference().child("user_images/\(userId).jpg")
        
        print("📤 Starting upload for user: \(userId)")
        print("📤 Image data size: \(imageData.count) bytes")
        print("📤 Storage path: user_images/\(userId).jpg")
        
        // Set metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year
        
        // Upload image using continuation for async/await
        let uploadMetadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            let uploadTask = imageRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error {
                    print("❌ Upload error: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("   Error domain: \(nsError.domain)")
                        print("   Error code: \(nsError.code)")
                      print("   Error userInfo: \(nsError.userInfo)")
                      print("   Error description: \(nsError.description)")
                    }
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    print("✅ Upload successful")
                    print("   Metadata path: \(metadata.path ?? "nil")")
                    print("   Metadata bucket: \(metadata.bucket ?? "nil")")
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error during upload"]))
                }
            }
            // Keep reference to prevent deallocation
            _ = uploadTask
        }
        
        print("✅ Upload metadata received, getting download URL...")
        print("⏳ Fetching download URL from storage reference...")
        
        // Get download URL - retry a few times if needed
        var downloadURL: URL?
        var lastError: Error?
        
        for attempt in 1...5 {
            do {
                downloadURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    imageRef.downloadURL { url, error in
                        if let error = error {
                            print("❌ Download URL error (attempt \(attempt)): \(error.localizedDescription)")
                            if let nsError = error as NSError? {
                                print("   Error code: \(nsError.code)")
                            }
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            print("✅ Got download URL: \(url.absoluteString)")
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: NSError(domain: "FirebaseStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                        }
                    }
                }
                break // Success, exit retry loop
            } catch {
                lastError = error
                print("⚠️ Attempt \(attempt) failed, waiting before retry...")
                if attempt < 5 {
                    // Wait longer between retries
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000) // 1s, 2s, 3s, 4s
                }
            }
        }
        
        guard let url = downloadURL else {
            // If we still can't get the URL, construct it manually as a fallback
            print("⚠️ Could not get download URL, constructing manually...")
            let bucket = storage.app.options.storageBucket ?? ""
            let encodedPath = "user_images/\(userId).jpg".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "user_images/\(userId).jpg"
            let manualURL = "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encodedPath)?alt=media"
            print("📝 Using constructed URL: \(manualURL)")
            return manualURL
        }
        
        return url.absoluteString
    }
    
    /// Download user image from Firebase Storage
    func downloadUserImage(userId: String) async throws -> Data {
        let imageRef = storage.reference().child("user_images/\(userId).jpg")
        let maxSize: Int64 = 10 * 1024 * 1024 // 10 MB max
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            imageRef.getData(maxSize: maxSize) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                }
            }
        }
    }
    
    /// Delete user image from Firebase Storage
    func deleteUserImage(userId: String) async throws {
        let imageRef = storage.reference().child("user_images/\(userId).jpg")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            imageRef.delete { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Image Caching

/// Manages local caching of user images
class UserImageCache {
    static let shared = UserImageCache()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    private init() {
        let cachePath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachePath.appendingPathComponent("UserImages", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Get cached image path for a user
    private func cachePath(for userId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(userId).jpg")
    }
    
    /// Save image to cache
    func saveImage(_ data: Data, for userId: String) {
        let path = cachePath(for: userId)
        try? data.write(to: path)
    }
    
    /// Load image from cache
    func loadImage(for userId: String) -> Data? {
        let path = cachePath(for: userId)
        return try? Data(contentsOf: path)
    }
    
    /// Check if cached image exists
    func hasCachedImage(for userId: String) -> Bool {
        let path = cachePath(for: userId)
        return fileManager.fileExists(atPath: path.path)
    }
    
    /// Delete cached image
    func deleteCachedImage(for userId: String) {
        let path = cachePath(for: userId)
        try? fileManager.removeItem(at: path)
    }
    
    /// Clear all cached images
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

