//
//  AdBannerView.swift
//  LicensePlateApp
//
//  Step 18 — SwiftUI banner placement for non-gameplay monetization surfaces.
//  COPPA F-7 (FR-18): banners exist only for fresh-confirmed non-child sessions;
//  posture transitions tear down live banners (reload for adults, removal for
//  child/hold sessions) so a banner loaded under an old config is never left showing.
//

import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdBannerView: View {
    let surface: AdSurface
    var isPreviewPlaceholder = false

    /// FR-18/FR-19 projection (decided by services; this view only renders it).
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared

    var body: some View {
        Group {
            if isPreviewPlaceholder {
                placeholder
            } else if childPostures.isAdDisplayEligible {
                #if canImport(GoogleMobileAds)
                AdMobBannerRepresentable(surface: surface)
                    .frame(width: 320, height: 50)
                    .accessibilityLabel("Sponsored message".localized)
                    .accessibilityAddTraits(.isStaticText)
                #else
                placeholder
                #endif
            }
            // Child/held sessions: no banner and no placeholder (FR-18 removal).
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
        context.coordinator.bind(banner)
        // FR-19 fail-closed: even though this view only exists for eligible postures,
        // re-check at load time so a same-runloop flip can never issue a request.
        if ChildSessionPostureCoordinator.shared.isAdDisplayEligible {
            banner.load(AdMobService.shared.makeRequest())
        } else {
            banner.isHidden = true
        }
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(surface: surface)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let surface: AdSurface
        private weak var banner: BannerView?
        private var postureObserver: NSObjectProtocol?

        init(surface: AdSurface) {
            self.surface = surface
        }

        deinit {
            if let postureObserver {
                NotificationCenter.default.removeObserver(postureObserver)
            }
        }

        /// FR-18: on any posture transition, tear down the live banner — reload under
        /// the freshly stamped config for eligible sessions, hide (and never reuse)
        /// for child/held sessions. SwiftUI also removes the whole view; this is the
        /// UIKit-level belt-and-braces for a banner instance that is still alive.
        func bind(_ banner: BannerView) {
            self.banner = banner
            guard postureObserver == nil else { return }
            postureObserver = NotificationCenter.default.addObserver(
                forName: .adIdentityDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let eligible = (notification.userInfo?[AdIdentityChangeKeys.isAdDisplayEligible] as? Bool) ?? false
                MainActor.assumeIsolated {
                    self?.handlePostureChange(isAdDisplayEligible: eligible)
                }
            }
        }

        @MainActor
        private func handlePostureChange(isAdDisplayEligible: Bool) {
            guard let banner else { return }
            if isAdDisplayEligible {
                banner.isHidden = false
                banner.load(AdMobService.shared.makeRequest())
            } else {
                banner.isHidden = true
            }
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
