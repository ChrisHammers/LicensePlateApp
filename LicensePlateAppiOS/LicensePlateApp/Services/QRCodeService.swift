//
//  QRCodeService.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import UIKit
import AVFoundation
import CoreImage

@MainActor
class QRCodeService {
    static let shared = QRCodeService()
    
    private init() {}
    
    // MARK: - Generate QR Code
    
    /// Generate QR code image from string
    func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        
        guard let output = filter.outputImage?.transformed(by: transform) else {
            return nil
        }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Generate QR code from deep link URL
    func generateQRCode(from url: URL) -> UIImage? {
        return generateQRCode(from: url.absoluteString)
    }
    
    // MARK: - Scan QR Code
    
    /// Check if camera is available for QR scanning
    func isCameraAvailable() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) != .denied
    }
    
    /// Request camera permission
    func requestCameraPermission() async -> Bool {
        let status = await AVCaptureDevice.requestAccess(for: .video)
        return status
    }
}

