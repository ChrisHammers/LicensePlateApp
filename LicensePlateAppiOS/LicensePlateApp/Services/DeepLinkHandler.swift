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

    var id: String {
        switch self {
        case .friendInvite(let inviteId):
            return "friend-\(inviteId)"
        case .familyInvite(let inviteId, let familyId):
            return "family-\(inviteId)-\(familyId)"
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
        let path = components?.path ?? ""
        let queryItems = components?.queryItems ?? []
        
        // Parse query parameters
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }
        
        // Handle invite paths
        if path.hasPrefix("/invite/friend") {
            if let inviteId = params["inviteId"] {
                AnalyticsService.shared.log(.deepLinkOpened(type: "friend", params: params))
                return .friendInvite(inviteId: inviteId)
            }
        } else if path.hasPrefix("/invite/family") {
            if let inviteId = params["inviteId"],
               let familyId = params["familyId"] {
                AnalyticsService.shared.log(.deepLinkOpened(type: "family", params: params))
                return .familyInvite(inviteId: inviteId, familyId: familyId)
            }
        }
        
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
}

