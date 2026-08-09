//
//  AdBannerView.swift
//  LicensePlateApp
//
//  Step 18 — SwiftUI banner placement for non-gameplay monetization surfaces.
//

import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdBannerView: View {
    let surface: AdSurface
    var isPreviewPlaceholder = false

    var body: some View {
        Group {
            if isPreviewPlaceholder {
                placeholder
            } else {
                #if canImport(GoogleMobileAds)
                AdMobBannerRepresentable(surface: surface)
                    .frame(width: 320, height: 50)
                    .accessibilityLabel("Sponsored message".localized)
                    .accessibilityAddTraits(.isStaticText)
                #else
                placeholder
                #endif
            }
        }
    }

    private var placeholder: some View {
        Text("Sponsored message".localized)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.Theme.softBrown)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
            .accessibilityLabel("Sponsored message".localized)
            .accessibilityAddTraits(.isStaticText)
    }
}

#if canImport(GoogleMobileAds)
private struct AdMobBannerRepresentable: UIViewRepresentable {
    let surface: AdSurface

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdMobService.shared.adUnitId(for: surface)
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        banner.delegate = context.coordinator
        banner.load(AdMobService.shared.makeRequest())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(surface: surface)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let surface: AdSurface

        init(surface: AdSurface) {
            self.surface = surface
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AnalyticsService.shared.log(.adImpression(surface: surface.rawValue))
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AnalyticsService.shared.log(.adLoadFailed(surface: surface.rawValue, error: error.localizedDescription))
        }
    }
}
#endif

#Preview("Ad banner placeholder") {
    AdBannerView(surface: .travelLog, isPreviewPlaceholder: true)
        .padding()
}
