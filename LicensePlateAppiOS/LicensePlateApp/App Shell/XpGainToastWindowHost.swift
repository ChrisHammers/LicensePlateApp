//
//  XpGainToastWindowHost.swift
//  LicensePlateApp
//
//  Presents XP gain toasts in a dedicated UIWindow below reward modals.
//

import Combine
import SwiftUI
import UIKit

private final class XpGainToastPassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        guard let rootView = rootViewController?.view else { return hitView }
        return hitView === rootView ? nil : hitView
    }
}

struct XpGainToastWindowRoot: View {
    @ObservedObject var service: XpGainToastService

    var body: some View {
        XpGainToastOverlayContent(service: service)
    }
}

struct XpGainToastOverlayContent: View {
    @ObservedObject var service: XpGainToastService

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                if let presentation = service.presentation {
                    XpGainToastBanner(presentation: presentation) {
                        service.dismissManually()
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: service.presentation?.lines.map(\.id))
    }
}

@MainActor
final class XpGainToastWindowHost {

    static let shared = XpGainToastWindowHost()

    private var window: UIWindow?
    private var boundService: XpGainToastService?
    private var cancellables = Set<AnyCancellable>()
    private var isInstalled = false

    private init() {}

    func install(service: XpGainToastService) {
        guard !isInstalled else { return }
        isInstalled = true
        boundService = service

        service.$presentation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentation in
                if presentation != nil {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.boundService?.presentation != nil else { return }
                self?.show()
            }
            .store(in: &cancellables)

        if service.presentation != nil {
            show()
        }
    }

    private func show() {
        guard let service = boundService, service.presentation != nil else {
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
            let created = XpGainToastPassthroughWindow(windowScene: scene)
            created.windowLevel = .alert
            created.backgroundColor = .clear
            window = created
            overlayWindow = created

            let controller = UIHostingController(rootView: XpGainToastWindowRoot(service: service))
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
