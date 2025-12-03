//
//  RegionBoundaries.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import CoreLocation

/// Approximate boundary polygons for license plate regions
/// Using simplified polygons (4-8 points) that roughly outline each state/province
struct RegionBoundaries {
    /// Get approximate boundary coordinates for a region
    /// Returns an array of CLLocationCoordinate2D representing a polygon
    static func boundary(for regionId: String) -> [CLLocationCoordinate2D] {
        return boundaries[regionId] ?? []
    }
    
    /// All region boundaries
    static let boundaries: [String: [CLLocationCoordinate2D]] = {
        var bounds: [String: [CLLocationCoordinate2D]] = [:]
        
        // United States - Approximate rectangular boundaries for each state
        // Format: [SW, SE, NE, NW] corners (simplified rectangles)
        
        // Alabama
        bounds["us-al"] = [
            CLLocationCoordinate2D(latitude: 30.144, longitude: -88.473), // SW
            CLLocationCoordinate2D(latitude: 30.144, longitude: -84.889), // SE
            CLLocationCoordinate2D(latitude: 35.008, longitude: -84.889), // NE
            CLLocationCoordinate2D(latitude: 35.008, longitude: -88.473)  // NW
        ]
        
        // Alaska - Large bounding box
        bounds["us-ak"] = [
            CLLocationCoordinate2D(latitude: 51.214, longitude: -179.148), // SW
            CLLocationCoordinate2D(latitude: 51.214, longitude: -129.979), // SE
            CLLocationCoordinate2D(latitude: 71.538, longitude: -129.979), // NE
            CLLocationCoordinate2D(latitude: 71.538, longitude: -179.148)  // NW
        ]
        
        // Arizona
        bounds["us-az"] = [
            CLLocationCoordinate2D(latitude: 31.332, longitude: -114.818), // SW
            CLLocationCoordinate2D(latitude: 31.332, longitude: -109.045), // SE
            CLLocationCoordinate2D(latitude: 37.004, longitude: -109.045), // NE
            CLLocationCoordinate2D(latitude: 37.004, longitude: -114.818)  // NW
        ]
        
        // Arkansas
        bounds["us-ar"] = [
            CLLocationCoordinate2D(latitude: 33.004, longitude: -94.618), // SW
            CLLocationCoordinate2D(latitude: 33.004, longitude: -89.644), // SE
            CLLocationCoordinate2D(latitude: 36.500, longitude: -89.644), // NE
            CLLocationCoordinate2D(latitude: 36.500, longitude: -94.618)  // NW
        ]
        
        // California
        bounds["us-ca"] = [
            CLLocationCoordinate2D(latitude: 32.528, longitude: -124.482), // SW
            CLLocationCoordinate2D(latitude: 32.528, longitude: -114.131), // SE
            CLLocationCoordinate2D(latitude: 42.010, longitude: -114.131), // NE
            CLLocationCoordinate2D(latitude: 42.010, longitude: -124.482)  // NW
        ]
        
        // Colorado
        bounds["us-co"] = [
            CLLocationCoordinate2D(latitude: 36.993, longitude: -109.050), // SW
            CLLocationCoordinate2D(latitude: 36.993, longitude: -102.042), // SE
            CLLocationCoordinate2D(latitude: 41.003, longitude: -102.042), // NE
            CLLocationCoordinate2D(latitude: 41.003, longitude: -109.050)  // NW
        ]
        
        // Connecticut
        bounds["us-ct"] = [
            CLLocationCoordinate2D(latitude: 40.950, longitude: -73.727), // SW
            CLLocationCoordinate2D(latitude: 40.950, longitude: -71.787), // SE
            CLLocationCoordinate2D(latitude: 42.051, longitude: -71.787), // NE
            CLLocationCoordinate2D(latitude: 42.051, longitude: -73.727)  // NW
        ]
        
        // Delaware
        bounds["us-de"] = [
            CLLocationCoordinate2D(latitude: 38.451, longitude: -75.789), // SW
            CLLocationCoordinate2D(latitude: 38.451, longitude: -75.048), // SE
            CLLocationCoordinate2D(latitude: 39.839, longitude: -75.048), // NE
            CLLocationCoordinate2D(latitude: 39.839, longitude: -75.789)  // NW
        ]
        
        // Florida
        bounds["us-fl"] = [
            CLLocationCoordinate2D(latitude: 24.521, longitude: -87.635), // SW
            CLLocationCoordinate2D(latitude: 24.521, longitude: -80.031), // SE
            CLLocationCoordinate2D(latitude: 31.001, longitude: -80.031), // NE
            CLLocationCoordinate2D(latitude: 31.001, longitude: -87.635)  // NW
        ]
        
        // Georgia
        bounds["us-ga"] = [
            CLLocationCoordinate2D(latitude: 30.356, longitude: -85.605), // SW
            CLLocationCoordinate2D(latitude: 30.356, longitude: -80.840), // SE
            CLLocationCoordinate2D(latitude: 35.001, longitude: -80.840), // NE
            CLLocationCoordinate2D(latitude: 35.001, longitude: -85.605)  // NW
        ]
        
        // Hawaii - Multiple islands, using main island bounding box
        bounds["us-hi"] = [
            CLLocationCoordinate2D(latitude: 18.910, longitude: -160.247), // SW
            CLLocationCoordinate2D(latitude: 18.910, longitude: -154.806), // SE
            CLLocationCoordinate2D(latitude: 22.338, longitude: -154.806), // NE
            CLLocationCoordinate2D(latitude: 22.338, longitude: -160.247)  // NW
        ]
        
        // Idaho
        bounds["us-id"] = [
            CLLocationCoordinate2D(latitude: 41.988, longitude: -117.243), // SW
            CLLocationCoordinate2D(latitude: 41.988, longitude: -111.043), // SE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -111.043), // NE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -117.243)  // NW
        ]
        
        // Illinois
        bounds["us-il"] = [
            CLLocationCoordinate2D(latitude: 36.970, longitude: -91.513), // SW
            CLLocationCoordinate2D(latitude: 36.970, longitude: -87.495), // SE
            CLLocationCoordinate2D(latitude: 42.508, longitude: -87.495), // NE
            CLLocationCoordinate2D(latitude: 42.508, longitude: -91.513)  // NW
        ]
        
        // Indiana
        bounds["us-in"] = [
            CLLocationCoordinate2D(latitude: 37.771, longitude: -88.098), // SW
            CLLocationCoordinate2D(latitude: 37.771, longitude: -84.784), // SE
            CLLocationCoordinate2D(latitude: 41.761, longitude: -84.784), // NE
            CLLocationCoordinate2D(latitude: 41.761, longitude: -88.098)  // NW
        ]
        
        // Iowa
        bounds["us-ia"] = [
            CLLocationCoordinate2D(latitude: 40.375, longitude: -96.639), // SW
            CLLocationCoordinate2D(latitude: 40.375, longitude: -90.140), // SE
            CLLocationCoordinate2D(latitude: 43.501, longitude: -90.140), // NE
            CLLocationCoordinate2D(latitude: 43.501, longitude: -96.639)  // NW
        ]
        
        // Kansas
        bounds["us-ks"] = [
            CLLocationCoordinate2D(latitude: 36.993, longitude: -102.042), // SW
            CLLocationCoordinate2D(latitude: 36.993, longitude: -94.588), // SE
            CLLocationCoordinate2D(latitude: 40.003, longitude: -94.588), // NE
            CLLocationCoordinate2D(latitude: 40.003, longitude: -102.042)  // NW
        ]
        
        // Kentucky
        bounds["us-ky"] = [
            CLLocationCoordinate2D(latitude: 36.497, longitude: -89.571), // SW
            CLLocationCoordinate2D(latitude: 36.497, longitude: -81.964), // SE
            CLLocationCoordinate2D(latitude: 39.148, longitude: -81.964), // NE
            CLLocationCoordinate2D(latitude: 39.148, longitude: -89.571)  // NW
        ]
        
        // Louisiana
        bounds["us-la"] = [
            CLLocationCoordinate2D(latitude: 28.928, longitude: -94.043), // SW
            CLLocationCoordinate2D(latitude: 28.928, longitude: -88.817), // SE
            CLLocationCoordinate2D(latitude: 33.019, longitude: -88.817), // NE
            CLLocationCoordinate2D(latitude: 33.019, longitude: -94.043)  // NW
        ]
        
        // Maine
        bounds["us-me"] = [
            CLLocationCoordinate2D(latitude: 43.064, longitude: -71.084), // SW
            CLLocationCoordinate2D(latitude: 43.064, longitude: -66.949), // SE
            CLLocationCoordinate2D(latitude: 47.460, longitude: -66.949), // NE
            CLLocationCoordinate2D(latitude: 47.460, longitude: -71.084)  // NW
        ]
        
        // Maryland
        bounds["us-md"] = [
            CLLocationCoordinate2D(latitude: 37.886, longitude: -79.488), // SW
            CLLocationCoordinate2D(latitude: 37.886, longitude: -75.049), // SE
            CLLocationCoordinate2D(latitude: 39.722, longitude: -75.049), // NE
            CLLocationCoordinate2D(latitude: 39.722, longitude: -79.488)  // NW
        ]
        
        // Massachusetts
        bounds["us-ma"] = [
            CLLocationCoordinate2D(latitude: 41.187, longitude: -73.508), // SW
            CLLocationCoordinate2D(latitude: 41.187, longitude: -69.858), // SE
            CLLocationCoordinate2D(latitude: 42.887, longitude: -69.858), // NE
            CLLocationCoordinate2D(latitude: 42.887, longitude: -73.508)  // NW
        ]
        
        // Michigan - Two peninsulas, using main bounding box
        bounds["us-mi"] = [
            CLLocationCoordinate2D(latitude: 41.696, longitude: -90.418), // SW
            CLLocationCoordinate2D(latitude: 41.696, longitude: -82.123), // SE
            CLLocationCoordinate2D(latitude: 48.303, longitude: -82.123), // NE
            CLLocationCoordinate2D(latitude: 48.303, longitude: -90.418)  // NW
        ]
        
        // Minnesota
        bounds["us-mn"] = [
            CLLocationCoordinate2D(latitude: 43.499, longitude: -97.239), // SW
            CLLocationCoordinate2D(latitude: 43.499, longitude: -89.483), // SE
            CLLocationCoordinate2D(latitude: 49.384, longitude: -89.483), // NE
            CLLocationCoordinate2D(latitude: 49.384, longitude: -97.239)  // NW
        ]
        
        // Mississippi
        bounds["us-ms"] = [
            CLLocationCoordinate2D(latitude: 30.144, longitude: -91.655), // SW
            CLLocationCoordinate2D(latitude: 30.144, longitude: -88.098), // SE
            CLLocationCoordinate2D(latitude: 34.996, longitude: -88.098), // NE
            CLLocationCoordinate2D(latitude: 34.996, longitude: -91.655)  // NW
        ]
        
        // Missouri
        bounds["us-mo"] = [
            CLLocationCoordinate2D(latitude: 35.996, longitude: -95.774), // SW
            CLLocationCoordinate2D(latitude: 35.996, longitude: -89.099), // SE
            CLLocationCoordinate2D(latitude: 40.614, longitude: -89.099), // NE
            CLLocationCoordinate2D(latitude: 40.614, longitude: -95.774)  // NW
        ]
        
        // Montana
        bounds["us-mt"] = [
            CLLocationCoordinate2D(latitude: 44.358, longitude: -116.050), // SW
            CLLocationCoordinate2D(latitude: 44.358, longitude: -104.040), // SE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -104.040), // NE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -116.050)  // NW
        ]
        
        // Nebraska
        bounds["us-ne"] = [
            CLLocationCoordinate2D(latitude: 39.999, longitude: -104.053), // SW
            CLLocationCoordinate2D(latitude: 39.999, longitude: -95.309), // SE
            CLLocationCoordinate2D(latitude: 43.001, longitude: -95.309), // NE
            CLLocationCoordinate2D(latitude: 43.001, longitude: -104.053)  // NW
        ]
        
        // Nevada
        bounds["us-nv"] = [
            CLLocationCoordinate2D(latitude: 35.002, longitude: -120.006), // SW
            CLLocationCoordinate2D(latitude: 35.002, longitude: -114.040), // SE
            CLLocationCoordinate2D(latitude: 42.002, longitude: -114.040), // NE
            CLLocationCoordinate2D(latitude: 42.002, longitude: -120.006)  // NW
        ]
        
        // New Hampshire
        bounds["us-nh"] = [
            CLLocationCoordinate2D(latitude: 42.697, longitude: -72.557), // SW
            CLLocationCoordinate2D(latitude: 42.697, longitude: -70.610), // SE
            CLLocationCoordinate2D(latitude: 45.305, longitude: -70.610), // NE
            CLLocationCoordinate2D(latitude: 45.305, longitude: -72.557)  // NW
        ]
        
        // New Jersey
        bounds["us-nj"] = [
            CLLocationCoordinate2D(latitude: 38.928, longitude: -75.559), // SW
            CLLocationCoordinate2D(latitude: 38.928, longitude: -73.894), // SE
            CLLocationCoordinate2D(latitude: 41.357, longitude: -73.894), // NE
            CLLocationCoordinate2D(latitude: 41.357, longitude: -75.559)  // NW
        ]
        
        // New Mexico
        bounds["us-nm"] = [
            CLLocationCoordinate2D(latitude: 31.332, longitude: -109.050), // SW
            CLLocationCoordinate2D(latitude: 31.332, longitude: -103.002), // SE
            CLLocationCoordinate2D(latitude: 37.000, longitude: -103.002), // NE
            CLLocationCoordinate2D(latitude: 37.000, longitude: -109.050)  // NW
        ]
        
        // New York
        bounds["us-ny"] = [
            CLLocationCoordinate2D(latitude: 40.477, longitude: -79.762), // SW
            CLLocationCoordinate2D(latitude: 40.477, longitude: -71.856), // SE
            CLLocationCoordinate2D(latitude: 45.016, longitude: -71.856), // NE
            CLLocationCoordinate2D(latitude: 45.016, longitude: -79.762)  // NW
        ]
        
        // North Carolina
        bounds["us-nc"] = [
            CLLocationCoordinate2D(latitude: 33.842, longitude: -84.322), // SW
            CLLocationCoordinate2D(latitude: 33.842, longitude: -75.459), // SE
            CLLocationCoordinate2D(latitude: 36.588, longitude: -75.459), // NE
            CLLocationCoordinate2D(latitude: 36.588, longitude: -84.322)  // NW
        ]
        
        // North Dakota
        bounds["us-nd"] = [
            CLLocationCoordinate2D(latitude: 45.935, longitude: -104.050), // SW
            CLLocationCoordinate2D(latitude: 45.935, longitude: -96.554), // SE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -96.554), // NE
            CLLocationCoordinate2D(latitude: 49.001, longitude: -104.050)  // NW
        ]
        
        // Ohio
        bounds["us-oh"] = [
            CLLocationCoordinate2D(latitude: 38.403, longitude: -84.820), // SW
            CLLocationCoordinate2D(latitude: 38.403, longitude: -80.519), // SE
            CLLocationCoordinate2D(latitude: 41.978, longitude: -80.519), // NE
            CLLocationCoordinate2D(latitude: 41.978, longitude: -84.820)  // NW
        ]
        
        // Oklahoma
        bounds["us-ok"] = [
            CLLocationCoordinate2D(latitude: 33.619, longitude: -103.002), // SW
            CLLocationCoordinate2D(latitude: 33.619, longitude: -94.431), // SE
            CLLocationCoordinate2D(latitude: 37.002, longitude: -94.431), // NE
            CLLocationCoordinate2D(latitude: 37.002, longitude: -103.002)  // NW
        ]
        
        // Oregon
        bounds["us-or"] = [
            CLLocationCoordinate2D(latitude: 41.992, longitude: -124.566), // SW
            CLLocationCoordinate2D(latitude: 41.992, longitude: -116.463), // SE
            CLLocationCoordinate2D(latitude: 46.292, longitude: -116.463), // NE
            CLLocationCoordinate2D(latitude: 46.292, longitude: -124.566)  // NW
        ]
        
        // Pennsylvania
        bounds["us-pa"] = [
            CLLocationCoordinate2D(latitude: 39.719, longitude: -80.519), // SW
            CLLocationCoordinate2D(latitude: 39.719, longitude: -74.689), // SE
            CLLocationCoordinate2D(latitude: 42.269, longitude: -74.689), // NE
            CLLocationCoordinate2D(latitude: 42.269, longitude: -80.519)  // NW
        ]
        
        // Rhode Island
        bounds["us-ri"] = [
            CLLocationCoordinate2D(latitude: 41.146, longitude: -71.862), // SW
            CLLocationCoordinate2D(latitude: 41.146, longitude: -71.120), // SE
            CLLocationCoordinate2D(latitude: 42.019, longitude: -71.120), // NE
            CLLocationCoordinate2D(latitude: 42.019, longitude: -71.862)  // NW
        ]
        
        // South Carolina
        bounds["us-sc"] = [
            CLLocationCoordinate2D(latitude: 32.035, longitude: -83.354), // SW
            CLLocationCoordinate2D(latitude: 32.035, longitude: -78.542), // SE
            CLLocationCoordinate2D(latitude: 35.215, longitude: -78.542), // NE
            CLLocationCoordinate2D(latitude: 35.215, longitude: -83.354)  // NW
        ]
        
        // South Dakota
        bounds["us-sd"] = [
            CLLocationCoordinate2D(latitude: 42.480, longitude: -104.058), // SW
            CLLocationCoordinate2D(latitude: 42.480, longitude: -96.436), // SE
            CLLocationCoordinate2D(latitude: 45.946, longitude: -96.436), // NE
            CLLocationCoordinate2D(latitude: 45.946, longitude: -104.058)  // NW
        ]
        
        // Tennessee
        bounds["us-tn"] = [
            CLLocationCoordinate2D(latitude: 34.983, longitude: -90.310), // SW
            CLLocationCoordinate2D(latitude: 34.983, longitude: -81.647), // SE
            CLLocationCoordinate2D(latitude: 36.678, longitude: -81.647), // NE
            CLLocationCoordinate2D(latitude: 36.678, longitude: -90.310)  // NW
        ]
        
        // Texas
        bounds["us-tx"] = [
            CLLocationCoordinate2D(latitude: 25.837, longitude: -106.646), // SW
            CLLocationCoordinate2D(latitude: 25.837, longitude: -93.508), // SE
            CLLocationCoordinate2D(latitude: 36.501, longitude: -93.508), // NE
            CLLocationCoordinate2D(latitude: 36.501, longitude: -106.646)  // NW
        ]
        
        // Utah
        bounds["us-ut"] = [
            CLLocationCoordinate2D(latitude: 36.998, longitude: -114.053), // SW
            CLLocationCoordinate2D(latitude: 36.998, longitude: -109.045), // SE
            CLLocationCoordinate2D(latitude: 42.001, longitude: -109.045), // NE
            CLLocationCoordinate2D(latitude: 42.001, longitude: -114.053)  // NW
        ]
        
        // Vermont
        bounds["us-vt"] = [
            CLLocationCoordinate2D(latitude: 42.727, longitude: -73.438), // SW
            CLLocationCoordinate2D(latitude: 42.727, longitude: -71.465), // SE
            CLLocationCoordinate2D(latitude: 45.016, longitude: -71.465), // NE
            CLLocationCoordinate2D(latitude: 45.016, longitude: -73.438)  // NW
        ]
        
        // Virginia
        bounds["us-va"] = [
            CLLocationCoordinate2D(latitude: 36.542, longitude: -83.675), // SW
            CLLocationCoordinate2D(latitude: 36.542, longitude: -75.242), // SE
            CLLocationCoordinate2D(latitude: 39.466, longitude: -75.242), // NE
            CLLocationCoordinate2D(latitude: 39.466, longitude: -83.675)  // NW
        ]
        
        // Washington
        bounds["us-wa"] = [
            CLLocationCoordinate2D(latitude: 45.543, longitude: -124.763), // SW
            CLLocationCoordinate2D(latitude: 45.543, longitude: -116.916), // SE
            CLLocationCoordinate2D(latitude: 49.002, longitude: -116.916), // NE
            CLLocationCoordinate2D(latitude: 49.002, longitude: -124.763)  // NW
        ]
        
        // West Virginia
        bounds["us-wv"] = [
            CLLocationCoordinate2D(latitude: 37.201, longitude: -82.644), // SW
            CLLocationCoordinate2D(latitude: 37.201, longitude: -77.719), // SE
            CLLocationCoordinate2D(latitude: 40.638, longitude: -77.719), // NE
            CLLocationCoordinate2D(latitude: 40.638, longitude: -82.644)  // NW
        ]
        
        // Wisconsin
        bounds["us-wi"] = [
            CLLocationCoordinate2D(latitude: 42.491, longitude: -92.889), // SW
            CLLocationCoordinate2D(latitude: 42.491, longitude: -86.249), // SE
            CLLocationCoordinate2D(latitude: 47.081, longitude: -86.249), // NE
            CLLocationCoordinate2D(latitude: 47.081, longitude: -92.889)  // NW
        ]
        
        // Wyoming
        bounds["us-wy"] = [
            CLLocationCoordinate2D(latitude: 40.996, longitude: -111.055), // SW
            CLLocationCoordinate2D(latitude: 40.996, longitude: -104.053), // SE
            CLLocationCoordinate2D(latitude: 45.006, longitude: -104.053), // NE
            CLLocationCoordinate2D(latitude: 45.006, longitude: -111.055)  // NW
        ]
        
        // District of Columbia
        bounds["us-dc"] = [
            CLLocationCoordinate2D(latitude: 38.791, longitude: -77.120), // SW
            CLLocationCoordinate2D(latitude: 38.791, longitude: -76.910), // SE
            CLLocationCoordinate2D(latitude: 39.000, longitude: -76.910), // NE
            CLLocationCoordinate2D(latitude: 39.000, longitude: -77.120)  // NW
        ]
        
        // Puerto Rico
        bounds["us-pr"] = [
            CLLocationCoordinate2D(latitude: 17.881, longitude: -67.271), // SW
            CLLocationCoordinate2D(latitude: 17.881, longitude: -65.220), // SE
            CLLocationCoordinate2D(latitude: 18.520, longitude: -65.220), // NE
            CLLocationCoordinate2D(latitude: 18.520, longitude: -67.271)  // NW
        ]
        
        // Guam
        bounds["us-gu"] = [
            CLLocationCoordinate2D(latitude: 13.182, longitude: 144.564), // SW
            CLLocationCoordinate2D(latitude: 13.182, longitude: 145.011), // SE
            CLLocationCoordinate2D(latitude: 13.706, longitude: 145.011), // NE
            CLLocationCoordinate2D(latitude: 13.706, longitude: 144.564)  // NW
        ]
        
        // US Virgin Islands
        bounds["us-vi"] = [
            CLLocationCoordinate2D(latitude: 17.624, longitude: -65.085), // SW
            CLLocationCoordinate2D(latitude: 17.624, longitude: -64.565), // SE
            CLLocationCoordinate2D(latitude: 18.464, longitude: -64.565), // NE
            CLLocationCoordinate2D(latitude: 18.464, longitude: -65.085)  // NW
        ]
        
        // American Samoa
        bounds["us-as"] = [
            CLLocationCoordinate2D(latitude: -14.760, longitude: -171.092), // SW
            CLLocationCoordinate2D(latitude: -14.760, longitude: -168.143), // SE
            CLLocationCoordinate2D(latitude: -11.050, longitude: -168.143), // NE
            CLLocationCoordinate2D(latitude: -11.050, longitude: -171.092)  // NW
        ]
        
        // Northern Mariana Islands
        bounds["us-mp"] = [
            CLLocationCoordinate2D(latitude: 14.036, longitude: 144.886), // SW
            CLLocationCoordinate2D(latitude: 14.036, longitude: 146.065), // SE
            CLLocationCoordinate2D(latitude: 20.553, longitude: 146.065), // NE
            CLLocationCoordinate2D(latitude: 20.553, longitude: 144.886)  // NW
        ]
        
        // Canada - Provinces and Territories
        // Alberta
        bounds["ca-ab"] = [
            CLLocationCoordinate2D(latitude: 48.996, longitude: -120.001), // SW
            CLLocationCoordinate2D(latitude: 48.996, longitude: -110.005), // SE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -110.005), // NE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -120.001)  // NW
        ]
        
        // British Columbia
        bounds["ca-bc"] = [
            CLLocationCoordinate2D(latitude: 48.307, longitude: -139.059), // SW
            CLLocationCoordinate2D(latitude: 48.307, longitude: -114.032), // SE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -114.032), // NE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -139.059)  // NW
        ]
        
        // Manitoba
        bounds["ca-mb"] = [
            CLLocationCoordinate2D(latitude: 48.997, longitude: -102.001), // SW
            CLLocationCoordinate2D(latitude: 48.997, longitude: -89.000), // SE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -89.000), // NE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -102.001)  // NW
        ]
        
        // New Brunswick
        bounds["ca-nb"] = [
            CLLocationCoordinate2D(latitude: 44.562, longitude: -69.062), // SW
            CLLocationCoordinate2D(latitude: 44.562, longitude: -63.789), // SE
            CLLocationCoordinate2D(latitude: 48.075, longitude: -63.789), // NE
            CLLocationCoordinate2D(latitude: 48.075, longitude: -69.062)  // NW
        ]
        
        // Newfoundland and Labrador
        bounds["ca-nl"] = [
            CLLocationCoordinate2D(latitude: 46.618, longitude: -67.800), // SW
            CLLocationCoordinate2D(latitude: 46.618, longitude: -52.636), // SE
            CLLocationCoordinate2D(latitude: 60.417, longitude: -52.636), // NE
            CLLocationCoordinate2D(latitude: 60.417, longitude: -67.800)  // NW
        ]
        
        // Northwest Territories
        bounds["ca-nt"] = [
            CLLocationCoordinate2D(latitude: 60.000, longitude: -136.000), // SW
            CLLocationCoordinate2D(latitude: 60.000, longitude: -102.001), // SE
            CLLocationCoordinate2D(latitude: 78.787, longitude: -102.001), // NE
            CLLocationCoordinate2D(latitude: 78.787, longitude: -136.000)  // NW
        ]
        
        // Nova Scotia
        bounds["ca-ns"] = [
            CLLocationCoordinate2D(latitude: 43.360, longitude: -66.325), // SW
            CLLocationCoordinate2D(latitude: 43.360, longitude: -59.797), // SE
            CLLocationCoordinate2D(latitude: 47.035, longitude: -59.797), // NE
            CLLocationCoordinate2D(latitude: 47.035, longitude: -66.325)  // NW
        ]
        
        // Nunavut
        bounds["ca-nu"] = [
            CLLocationCoordinate2D(latitude: 51.660, longitude: -95.317), // SW
            CLLocationCoordinate2D(latitude: 51.660, longitude: -61.362), // SE
            CLLocationCoordinate2D(latitude: 83.111, longitude: -61.362), // NE
            CLLocationCoordinate2D(latitude: 83.111, longitude: -95.317)  // NW
        ]
        
        // Ontario
        bounds["ca-on"] = [
            CLLocationCoordinate2D(latitude: 41.675, longitude: -95.153), // SW
            CLLocationCoordinate2D(latitude: 41.675, longitude: -74.320), // SE
            CLLocationCoordinate2D(latitude: 56.865, longitude: -74.320), // NE
            CLLocationCoordinate2D(latitude: 56.865, longitude: -95.153)  // NW
        ]
        
        // Prince Edward Island
        bounds["ca-pe"] = [
            CLLocationCoordinate2D(latitude: 45.950, longitude: -64.417), // SW
            CLLocationCoordinate2D(latitude: 45.950, longitude: -61.900), // SE
            CLLocationCoordinate2D(latitude: 47.065, longitude: -61.900), // NE
            CLLocationCoordinate2D(latitude: 47.065, longitude: -64.417)  // NW
        ]
        
        // Quebec
        bounds["ca-qc"] = [
            CLLocationCoordinate2D(latitude: 44.992, longitude: -79.762), // SW
            CLLocationCoordinate2D(latitude: 44.992, longitude: -57.104), // SE
            CLLocationCoordinate2D(latitude: 62.613, longitude: -57.104), // NE
            CLLocationCoordinate2D(latitude: 62.613, longitude: -79.762)  // NW
        ]
        
        // Saskatchewan
        bounds["ca-sk"] = [
            CLLocationCoordinate2D(latitude: 48.996, longitude: -110.005), // SW
            CLLocationCoordinate2D(latitude: 48.996, longitude: -101.360), // SE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -101.360), // NE
            CLLocationCoordinate2D(latitude: 60.000, longitude: -110.005)  // NW
        ]
        
        // Yukon
        bounds["ca-yt"] = [
            CLLocationCoordinate2D(latitude: 60.000, longitude: -141.002), // SW
            CLLocationCoordinate2D(latitude: 60.000, longitude: -123.920), // SE
            CLLocationCoordinate2D(latitude: 69.637, longitude: -123.920), // NE
            CLLocationCoordinate2D(latitude: 69.637, longitude: -141.002)  // NW
        ]
        
        // Mexico - States
        // Using simplified rectangular boundaries for Mexican states
        // Aguascalientes
        bounds["mx-ags"] = [
            CLLocationCoordinate2D(latitude: 21.617, longitude: -102.862), // SW
            CLLocationCoordinate2D(latitude: 21.617, longitude: -101.720), // SE
            CLLocationCoordinate2D(latitude: 22.456, longitude: -101.720), // NE
            CLLocationCoordinate2D(latitude: 22.456, longitude: -102.862)  // NW
        ]
        
        // Baja California
        bounds["mx-bcn"] = [
            CLLocationCoordinate2D(latitude: 28.000, longitude: -117.127), // SW
            CLLocationCoordinate2D(latitude: 28.000, longitude: -112.726), // SE
            CLLocationCoordinate2D(latitude: 32.718, longitude: -112.726), // NE
            CLLocationCoordinate2D(latitude: 32.718, longitude: -117.127)  // NW
        ]
        
        // Baja California Sur
        bounds["mx-bcs"] = [
            CLLocationCoordinate2D(latitude: 22.870, longitude: -115.227), // SW
            CLLocationCoordinate2D(latitude: 22.870, longitude: -109.226), // SE
            CLLocationCoordinate2D(latitude: 28.000, longitude: -109.226), // NE
            CLLocationCoordinate2D(latitude: 28.000, longitude: -115.227)  // NW
        ]
        
        // Campeche
        bounds["mx-cam"] = [
            CLLocationCoordinate2D(latitude: 17.490, longitude: -92.463), // SW
            CLLocationCoordinate2D(latitude: 17.490, longitude: -89.152), // SE
            CLLocationCoordinate2D(latitude: 20.850, longitude: -89.152), // NE
            CLLocationCoordinate2D(latitude: 20.850, longitude: -92.463)  // NW
        ]
        
        // Chiapas
        bounds["mx-chp"] = [
            CLLocationCoordinate2D(latitude: 14.532, longitude: -94.140), // SW
            CLLocationCoordinate2D(latitude: 14.532, longitude: -90.226), // SE
            CLLocationCoordinate2D(latitude: 17.817, longitude: -90.226), // NE
            CLLocationCoordinate2D(latitude: 17.817, longitude: -94.140)  // NW
        ]
        
        // Chihuahua
        bounds["mx-chh"] = [
            CLLocationCoordinate2D(latitude: 25.837, longitude: -109.995), // SW
            CLLocationCoordinate2D(latitude: 25.837, longitude: -103.302), // SE
            CLLocationCoordinate2D(latitude: 31.784, longitude: -103.302), // NE
            CLLocationCoordinate2D(latitude: 31.784, longitude: -109.995)  // NW
        ]
        
        // Coahuila
        bounds["mx-coa"] = [
            CLLocationCoordinate2D(latitude: 25.837, longitude: -103.302), // SW
            CLLocationCoordinate2D(latitude: 25.837, longitude: -99.519), // SE
            CLLocationCoordinate2D(latitude: 29.817, longitude: -99.519), // NE
            CLLocationCoordinate2D(latitude: 29.817, longitude: -103.302)  // NW
        ]
        
        // Colima
        bounds["mx-col"] = [
            CLLocationCoordinate2D(latitude: 18.800, longitude: -104.577), // SW
            CLLocationCoordinate2D(latitude: 18.800, longitude: -103.329), // SE
            CLLocationCoordinate2D(latitude: 19.584, longitude: -103.329), // NE
            CLLocationCoordinate2D(latitude: 19.584, longitude: -104.577)  // NW
        ]
        
        // Durango
        bounds["mx-dur"] = [
            CLLocationCoordinate2D(latitude: 22.454, longitude: -107.100), // SW
            CLLocationCoordinate2D(latitude: 22.454, longitude: -102.479), // SE
            CLLocationCoordinate2D(latitude: 26.830, longitude: -102.479), // NE
            CLLocationCoordinate2D(latitude: 26.830, longitude: -107.100)  // NW
        ]
        
        // Guanajuato
        bounds["mx-gua"] = [
            CLLocationCoordinate2D(latitude: 19.920, longitude: -101.726), // SW
            CLLocationCoordinate2D(latitude: 19.920, longitude: -100.095), // SE
            CLLocationCoordinate2D(latitude: 21.920, longitude: -100.095), // NE
            CLLocationCoordinate2D(latitude: 21.920, longitude: -101.726)  // NW
        ]
        
        // Guerrero
        bounds["mx-gro"] = [
            CLLocationCoordinate2D(latitude: 16.185, longitude: -101.726), // SW
            CLLocationCoordinate2D(latitude: 16.185, longitude: -98.125), // SE
            CLLocationCoordinate2D(latitude: 18.791, longitude: -98.125), // NE
            CLLocationCoordinate2D(latitude: 18.791, longitude: -101.726)  // NW
        ]
        
        // Hidalgo
        bounds["mx-hid"] = [
            CLLocationCoordinate2D(latitude: 19.320, longitude: -99.519), // SW
            CLLocationCoordinate2D(latitude: 19.320, longitude: -97.722), // SE
            CLLocationCoordinate2D(latitude: 21.417, longitude: -97.722), // NE
            CLLocationCoordinate2D(latitude: 21.417, longitude: -99.519)  // NW
        ]
        
        // Jalisco
        bounds["mx-jal"] = [
            CLLocationCoordinate2D(latitude: 19.220, longitude: -105.692), // SW
            CLLocationCoordinate2D(latitude: 19.220, longitude: -101.726), // SE
            CLLocationCoordinate2D(latitude: 22.771, longitude: -101.726), // NE
            CLLocationCoordinate2D(latitude: 22.771, longitude: -105.692)  // NW
        ]
        
        // Mexico State
        bounds["mx-mex"] = [
            CLLocationCoordinate2D(latitude: 18.361, longitude: -100.245), // SW
            CLLocationCoordinate2D(latitude: 18.361, longitude: -98.650), // SE
            CLLocationCoordinate2D(latitude: 20.360, longitude: -98.650), // NE
            CLLocationCoordinate2D(latitude: 20.360, longitude: -100.245)  // NW
        ]
        
        // Michoacán
        bounds["mx-mic"] = [
            CLLocationCoordinate2D(latitude: 17.918, longitude: -103.302), // SW
            CLLocationCoordinate2D(latitude: 17.918, longitude: -100.245), // SE
            CLLocationCoordinate2D(latitude: 20.395, longitude: -100.245), // NE
            CLLocationCoordinate2D(latitude: 20.395, longitude: -103.302)  // NW
        ]
        
        // Morelos
        bounds["mx-mor"] = [
            CLLocationCoordinate2D(latitude: 18.361, longitude: -99.519), // SW
            CLLocationCoordinate2D(latitude: 18.361, longitude: -98.650), // SE
            CLLocationCoordinate2D(latitude: 19.320, longitude: -98.650), // NE
            CLLocationCoordinate2D(latitude: 19.320, longitude: -99.519)  // NW
        ]
        
        // Nayarit
        bounds["mx-nay"] = [
            CLLocationCoordinate2D(latitude: 20.456, longitude: -105.692), // SW
            CLLocationCoordinate2D(latitude: 20.456, longitude: -103.302), // SE
            CLLocationCoordinate2D(latitude: 22.771, longitude: -103.302), // NE
            CLLocationCoordinate2D(latitude: 22.771, longitude: -105.692)  // NW
        ]
        
        // Nuevo León
        bounds["mx-nle"] = [
            CLLocationCoordinate2D(latitude: 23.635, longitude: -100.245), // SW
            CLLocationCoordinate2D(latitude: 23.635, longitude: -98.650), // SE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -98.650), // NE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -100.245)  // NW
        ]
        
        // Oaxaca
        bounds["mx-oax"] = [
            CLLocationCoordinate2D(latitude: 15.617, longitude: -98.650), // SW
            CLLocationCoordinate2D(latitude: 15.617, longitude: -93.350), // SE
            CLLocationCoordinate2D(latitude: 18.654, longitude: -93.350), // NE
            CLLocationCoordinate2D(latitude: 18.654, longitude: -98.650)  // NW
        ]
        
        // Puebla
        bounds["mx-pue"] = [
            CLLocationCoordinate2D(latitude: 17.918, longitude: -98.650), // SW
            CLLocationCoordinate2D(latitude: 17.918, longitude: -96.726), // SE
            CLLocationCoordinate2D(latitude: 20.850, longitude: -96.726), // NE
            CLLocationCoordinate2D(latitude: 20.850, longitude: -98.650)  // NW
        ]
        
        // Querétaro
        bounds["mx-que"] = [
            CLLocationCoordinate2D(latitude: 20.000, longitude: -100.245), // SW
            CLLocationCoordinate2D(latitude: 20.000, longitude: -99.519), // SE
            CLLocationCoordinate2D(latitude: 21.417, longitude: -99.519), // NE
            CLLocationCoordinate2D(latitude: 21.417, longitude: -100.245)  // NW
        ]
        
        // Quintana Roo
        bounds["mx-roo"] = [
            CLLocationCoordinate2D(latitude: 17.490, longitude: -89.152), // SW
            CLLocationCoordinate2D(latitude: 17.490, longitude: -86.710), // SE
            CLLocationCoordinate2D(latitude: 21.617, longitude: -86.710), // NE
            CLLocationCoordinate2D(latitude: 21.617, longitude: -89.152)  // NW
        ]
        
        // San Luis Potosí
        bounds["mx-slp"] = [
            CLLocationCoordinate2D(latitude: 21.140, longitude: -100.245), // SW
            CLLocationCoordinate2D(latitude: 21.140, longitude: -98.125), // SE
            CLLocationCoordinate2D(latitude: 24.634, longitude: -98.125), // NE
            CLLocationCoordinate2D(latitude: 24.634, longitude: -100.245)  // NW
        ]
        
        // Sinaloa
        bounds["mx-sin"] = [
            CLLocationCoordinate2D(latitude: 22.454, longitude: -109.995), // SW
            CLLocationCoordinate2D(latitude: 22.454, longitude: -105.692), // SE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -105.692), // NE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -109.995)  // NW
        ]
        
        // Sonora
        bounds["mx-son"] = [
            CLLocationCoordinate2D(latitude: 26.704, longitude: -115.227), // SW
            CLLocationCoordinate2D(latitude: 26.704, longitude: -108.208), // SE
            CLLocationCoordinate2D(latitude: 32.718, longitude: -108.208), // NE
            CLLocationCoordinate2D(latitude: 32.718, longitude: -115.227)  // NW
        ]
        
        // Tabasco
        bounds["mx-tab"] = [
            CLLocationCoordinate2D(latitude: 17.149, longitude: -94.140), // SW
            CLLocationCoordinate2D(latitude: 17.149, longitude: -91.000), // SE
            CLLocationCoordinate2D(latitude: 18.654, longitude: -91.000), // NE
            CLLocationCoordinate2D(latitude: 18.654, longitude: -94.140)  // NW
        ]
        
        // Tamaulipas
        bounds["mx-tam"] = [
            CLLocationCoordinate2D(latitude: 22.249, longitude: -100.245), // SW
            CLLocationCoordinate2D(latitude: 22.249, longitude: -97.140), // SE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -97.140), // NE
            CLLocationCoordinate2D(latitude: 27.634, longitude: -100.245)  // NW
        ]
        
        // Tlaxcala
        bounds["mx-tla"] = [
            CLLocationCoordinate2D(latitude: 19.064, longitude: -98.650), // SW
            CLLocationCoordinate2D(latitude: 19.064, longitude: -97.722), // SE
            CLLocationCoordinate2D(latitude: 19.920, longitude: -97.722), // NE
            CLLocationCoordinate2D(latitude: 19.920, longitude: -98.650)  // NW
        ]
        
        // Veracruz
        bounds["mx-ver"] = [
            CLLocationCoordinate2D(latitude: 17.149, longitude: -98.650), // SW
            CLLocationCoordinate2D(latitude: 17.149, longitude: -93.350), // SE
            CLLocationCoordinate2D(latitude: 22.249, longitude: -93.350), // NE
            CLLocationCoordinate2D(latitude: 22.249, longitude: -98.650)  // NW
        ]
        
        // Yucatán
        bounds["mx-yuc"] = [
            CLLocationCoordinate2D(latitude: 19.500, longitude: -90.430), // SW
            CLLocationCoordinate2D(latitude: 19.500, longitude: -87.323), // SE
            CLLocationCoordinate2D(latitude: 21.617, longitude: -87.323), // NE
            CLLocationCoordinate2D(latitude: 21.617, longitude: -90.430)  // NW
        ]
        
        // Zacatecas
        bounds["mx-zac"] = [
            CLLocationCoordinate2D(latitude: 21.140, longitude: -104.577), // SW
            CLLocationCoordinate2D(latitude: 21.140, longitude: -100.245), // SE
            CLLocationCoordinate2D(latitude: 25.172, longitude: -100.245), // NE
            CLLocationCoordinate2D(latitude: 25.172, longitude: -104.577)  // NW
        ]
        
        // Mexico City (CDMX)
        bounds["mx-cmx"] = [
            CLLocationCoordinate2D(latitude: 19.042, longitude: -99.364), // SW
            CLLocationCoordinate2D(latitude: 19.042, longitude: -98.938), // SE
            CLLocationCoordinate2D(latitude: 19.592, longitude: -98.938), // NE
            CLLocationCoordinate2D(latitude: 19.592, longitude: -99.364)  // NW
        ]
        
        return bounds
    }()
}

