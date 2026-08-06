//
//  TripSummaryShareActivityItemSource.swift
//  LicensePlateApp
//
//  Named JPEG share item for the system share sheet. File URLs surface Photos / social
//  destinations better than raw UIImage, and let us control the shared filename.
//

import LinkPresentation
import UIKit
import UniformTypeIdentifiers

final class TripSummaryShareActivityItemSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let tripName: String
    let fileURL: URL

    /// System actions that clutter marketing/image share without helping Photos or social.
    /// Keeps Save Image, Messages, Mail, AirDrop, Copy, and Save to Files available.
    static let excludedActivityTypes: [UIActivity.ActivityType] = [
        .assignToContact,
        .addToReadingList,
        .print,
        .openInIBooks,
        .markupAsPDF,
        .postToWeibo,
        .postToTencentWeibo,
        .postToVimeo,
        .postToFlickr,
        .collaborationInviteWithLink,
        .collaborationCopyLink,
        .sharePlay
    ]

    /// Writes `image` as a JPEG into a temp file named from `tripName`.
    init?(image: UIImage, tripName: String, compressionQuality: CGFloat = 0.92) {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else { return nil }
        let fileName = Self.sanitizedFileName(from: tripName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        self.image = image
        self.tripName = tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "RoadTrip Royale"
            : tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileURL = url
        super.init()
    }

    static func sanitizedFileName(from tripName: String) -> String {
        let trimmed = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Trip" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = base
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
        let limited = String(cleaned.prefix(80))
        let tripPart = limited.isEmpty ? "Trip" : limited
        return "RoadTripRoyale-\(tripPart).jpg"
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        tripName
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.jpeg.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = tripName
        metadata.originalURL = fileURL
        metadata.url = fileURL
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}
