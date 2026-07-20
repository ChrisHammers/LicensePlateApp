//
//  DeepLinkHandler.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftUI
import Combine

enum DeepLinkDestination: Hashable, Identifiable {
    case friendInvite(inviteId: String)
    case familyInvite(inviteId: String, familyId: String)
    case tripInvite(inviteId: String)
    /// Creator/captain inbox: pending join requests for a family.
    case familyPendingApprovals(familyId: String)
    /// Open Family dashboard (e.g. after join approved).
    case familyHome(familyId: String)

    var id: String {
        switch self {
        case .friendInvite(let inviteId):
            return "friend-\(inviteId)"
        case .familyInvite(let inviteId, let familyId):
            return "family-\(inviteId)-\(familyId)"
        case .tripInvite(let inviteId):
            return "trip-\(inviteId)"
        case .familyPendingApprovals(let familyId):
            return "family-pending-\(familyId)"
        case .familyHome(let familyId):
            return "family-home-\(familyId)"
        }
    }
}

@MainActor
class DeepLinkHandler: ObservableObject {
    @Published var destination: DeepLinkDestination?
    
    static let shared = DeepLinkHandler()
    
    private init() {}

    func clearDestination() {
        destination = nil
    }
    
    /// Parse a deep link URL
    func handleURL(_ url: URL) -> DeepLinkDestination? {
        guard url.scheme == "roadtrip-royale" else {
            return nil
        }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""
        let path = components?.path ?? ""
        let queryItems = components?.queryItems ?? []
        
        // Parse query parameters
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        // Normalize `roadtrip-royale://invite/friend` (host+path) and `roadtrip-royale:/invite/friend` (path only).
        let routePath: String = {
            if path.hasPrefix("/invite/") || path.hasPrefix("/family/") {
                return path
            }
            if !host.isEmpty {
                let suffix = (path == "/" || path.isEmpty) ? "" : path
                return "/\(host)\(suffix)"
            }
            return path
        }()
        
        // Handle invite paths
        if routePath.hasPrefix("/invite/friend") {
            if let inviteId = params["inviteId"] {
                AnalyticsService.shared.log(.deepLinkOpened(type: "friend", params: params))
                return .friendInvite(inviteId: inviteId)
            }
        } else if routePath.hasPrefix("/invite/family") {
            if let inviteId = params["inviteId"],
               let familyId = params["familyId"] {
                AnalyticsService.shared.log(.deepLinkOpened(type: "family", params: params))
                return .familyInvite(inviteId: inviteId, familyId: familyId)
            }
        } else if routePath.hasPrefix("/invite/trip") {
            if let inviteId = params["inviteId"] {
                AnalyticsService.shared.log(.deepLinkOpened(type: "trip", params: params))
                return .tripInvite(inviteId: inviteId)
            }
        } else if routePath.hasPrefix("/family/") {
            let segments = routePath
                .split(separator: "/")
                .map(String.init)
            // ["family", "{familyId}"] or ["family", "{familyId}", "pending"]
            guard segments.count >= 2, segments[0] == "family" else { return nil }
            let familyId = segments[1]
            guard !familyId.isEmpty else { return nil }
            if segments.count >= 3, segments[2] == "pending" {
                AnalyticsService.shared.log(.deepLinkOpened(type: "family_pending", params: ["familyId": familyId]))
                return .familyPendingApprovals(familyId: familyId)
            }
            AnalyticsService.shared.log(.deepLinkOpened(type: "family_home", params: ["familyId": familyId]))
            return .familyHome(familyId: familyId)
        }
        
        return nil
    }

    /// Route a push/local notification payload into `destination` when it carries an invite deep link.
    /// Prefer `deepLink`; fall back to `type` + ids for older payloads. Non-invite payloads are ignored.
    func applyNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let destination = Self.destination(fromNotificationUserInfo: userInfo) {
            self.destination = destination
        }
    }

    /// Pure parse of FCM / UNNotification `userInfo` into an invite destination (or nil).
    static func destination(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> DeepLinkDestination? {
        if let deepLink = stringValue(userInfo["deepLink"]) ?? stringValue(userInfo["deep_link"]),
           let url = URL(string: deepLink),
           let destination = DeepLinkHandler.shared.handleURL(url) {
            return destination
        }

        let type = stringValue(userInfo["type"])
        let inviteId = stringValue(userInfo["inviteId"]) ?? stringValue(userInfo["invite_id"])
        let familyId = stringValue(userInfo["familyId"]) ?? stringValue(userInfo["family_id"])

        switch type {
        case "friend_invite":
            guard let inviteId else { return nil }
            AnalyticsService.shared.log(.deepLinkOpened(type: "friend", params: ["inviteId": inviteId, "source": "notification"]))
            return .friendInvite(inviteId: inviteId)
        case "family_invite":
            guard let inviteId,
                  let familyId else {
                return nil
            }
            AnalyticsService.shared.log(.deepLinkOpened(
                type: "family",
                params: ["inviteId": inviteId, "familyId": familyId, "source": "notification"]
            ))
            return .familyInvite(inviteId: inviteId, familyId: familyId)
        case "trip_invite":
            guard let inviteId else { return nil }
            AnalyticsService.shared.log(.deepLinkOpened(type: "trip", params: ["inviteId": inviteId, "source": "notification"]))
            return .tripInvite(inviteId: inviteId)
        case "family_join_request":
            guard let familyId else { return nil }
            AnalyticsService.shared.log(.deepLinkOpened(
                type: "family_pending",
                params: ["familyId": familyId, "source": "notification"]
            ))
            return .familyPendingApprovals(familyId: familyId)
        case "family_join_approved":
            guard let familyId else { return nil }
            AnalyticsService.shared.log(.deepLinkOpened(
                type: "family_home",
                params: ["familyId": familyId, "source": "notification"]
            ))
            return .familyHome(familyId: familyId)
        default:
            return nil
        }
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let string = any as? String, !string.isEmpty { return string }
        if let number = any as? NSNumber { return number.stringValue }
        return nil
    }
    
    /// Generate deep link URL for friend invite
    static func friendInviteURL(inviteId: String) -> URL {
        var components = URLComponents()
        components.scheme = "roadtrip-royale"
        components.path = "/invite/friend"
        components.queryItems = [URLQueryItem(name: "inviteId", value: inviteId)]
        return components.url!
    }
    
    /// Generate deep link URL for family invite
    static func familyInviteURL(inviteId: String, familyId: String) -> URL {
        var components = URLComponents()
        components.scheme = "roadtrip-royale"
        components.path = "/invite/family"
        components.queryItems = [
            URLQueryItem(name: "inviteId", value: inviteId),
            URLQueryItem(name: "familyId", value: familyId)
        ]
        return components.url!
    }

    /// Generate deep link URL for trip invite
    static func tripInviteURL(inviteId: String) -> URL {
        var components = URLComponents()
        components.scheme = "roadtrip-royale"
        components.path = "/invite/trip"
        components.queryItems = [URLQueryItem(name: "inviteId", value: inviteId)]
        return components.url!
    }

    /// Pending join approvals for a family (creator/captain).
    static func familyPendingApprovalsURL(familyId: String) -> URL {
        var components = URLComponents()
        components.scheme = "roadtrip-royale"
        components.path = "/family/\(familyId)/pending"
        return components.url!
    }

    /// Family home / dashboard deep link.
    static func familyHomeURL(familyId: String) -> URL {
        var components = URLComponents()
        components.scheme = "roadtrip-royale"
        components.path = "/family/\(familyId)"
        return components.url!
    }
}
