//
//  GoogleMapStyle.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import GoogleMaps

/// Custom map styles for Google Maps
struct GoogleMapStyle {
    /// Custom style optimized for region highlighting
    /// Mutes base map features to make region boundaries stand out
    static func regionHighlightStyle() -> GMSMapStyle? {
        let styleJSON = """
        [
          {
            "featureType": "all",
            "elementType": "geometry",
            "stylers": [
              { "saturation": -30 },
              { "lightness": 10 }
            ]
          },
          {
            "featureType": "water",
            "elementType": "geometry",
            "stylers": [
              { "color": "#e9e9e9" },
              { "lightness": 20 }
            ]
          },
          {
            "featureType": "landscape",
            "elementType": "geometry",
            "stylers": [
              { "color": "#f5f5f5" },
              { "lightness": 5 }
            ]
          },
          {
            "featureType": "road",
            "elementType": "geometry",
            "stylers": [
              { "color": "#ffffff" },
              { "lightness": 6 }
            ]
          },
          {
            "featureType": "road.highway",
            "elementType": "geometry",
            "stylers": [
              { "color": "#dadada" },
              { "lightness": 15 }
            ]
          },
          {
            "featureType": "administrative",
            "elementType": "geometry.stroke",
            "stylers": [
              { "color": "#a9a9a9" },
              { "lightness": 10 },
              { "weight": 0.5 }
            ]
          },
          {
            "featureType": "administrative",
            "elementType": "labels.text.fill",
            "stylers": [
              { "color": "#737373" },
              { "lightness": 20 }
            ]
          },
          {
            "featureType": "poi",
            "elementType": "all",
            "stylers": [
              { "visibility": "simplified" },
              { "saturation": -50 }
            ]
          },
          {
            "featureType": "transit",
            "elementType": "all",
            "stylers": [
              { "visibility": "off" }
            ]
          }
        ]
        """
        
        return try? GMSMapStyle(jsonString: styleJSON)
    }
    
    /// Standard muted style (less aggressive than region highlight)
    static func mutedStyle() -> GMSMapStyle? {
        let styleJSON = """
        [
          {
            "featureType": "all",
            "elementType": "geometry",
            "stylers": [
              { "saturation": -20 }
            ]
          },
          {
            "featureType": "water",
            "elementType": "geometry",
            "stylers": [
              { "lightness": 10 }
            ]
          },
          {
            "featureType": "poi",
            "elementType": "all",
            "stylers": [
              { "visibility": "simplified" }
            ]
          }
        ]
        """
        
        return try? GMSMapStyle(jsonString: styleJSON)
    }
    
    /// Get map style based on app preference
    static func styleFromPreference() -> GMSMapStyle? {
        let appMapStyleRaw = UserDefaults.standard.string(forKey: "appMapStyle") ?? AppMapStyle.standard.rawValue
        let mapStyle = AppMapStyle(rawValue: appMapStyleRaw) ?? .standard
        
        switch mapStyle {
        case .custom:
            return regionHighlightStyle()
        case .standard, .satellite:
            return nil // Use default Google Maps styling
        }
    }
}

