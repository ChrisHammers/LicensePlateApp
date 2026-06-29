//
//  RewardPopupWindowHost.swift
//  LicensePlateApp
//
//  Presents reward celebrations in a dedicated UIWindow above sheets and other modals.
//

import Combine
import SwiftUI
import UIKit

/// Root content for the overlay window; observes `RewardPresenter` for queue updates.
struct RewardPopupWindowRoot: View {
    @ObservedObject var presenter: RewardPresenter

    var body: some View {
        RewardPopupOverlayContent(presenter: presenter)
    }
}

/// Shared full-screen reward chrome (dimming + popup). Used by the overlay window and SwiftUI previews.
struct RewardPopupOverlayContent: View {
    @ObservedObject var presenter: RewardPresenter

    var body: some View {
        ZStack {
            if let event = presenter.current {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { presenter.dismiss() }
                RewardPopupView(event: event) { presenter.dismiss() }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: presenter.current?.id)
    }
}

@MainActor
final class RewardPopupWindowHost {

    static let shared = RewardPopupWindowHost()

    private var window: UIWindow?
    private var boundPresenter: RewardPresenter?
    private var cancellables = Set<AnyCancellable>()
    private var isInstalled = false

    private init() {}

    /// Call once at app launch. Observes `presenter.current` and shows/hides the overlay window.
    func install(presenter: RewardPresenter) {
        guard !isInstalled else { return }
        isInstalled = true
        boundPresenter = presenter

        presenter.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] current in
                if current != nil {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.boundPresenter?.current != nil else { return }
                self?.show()
            }
            .store(in: &cancellables)

        if presenter.current != nil {
            show()
        }
    }

    private func show() {
        guard let presenter = boundPresenter, presenter.current != nil else {
            hide()
            return
        }
        guard let scene = activeWindowScene() else { return }

        if let existing = window, existing.windowScene !== scene {
            tearDownWindow()
        }

        let overlayWindow: UIWindow
        if let window {
            overlayWindow = window
        } else {
            let created = UIWindow(windowScene: scene)
            created.windowLevel = .alert + 1
            created.backgroundColor = .clear
            window = created
            overlayWindow = created

            let controller = UIHostingController(rootView: RewardPopupWindowRoot(presenter: presenter))
            controller.view.backgroundColor = .clear
            overlayWindow.rootViewController = controller
        }

        overlayWindow.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
    }

    private func tearDownWindow() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
