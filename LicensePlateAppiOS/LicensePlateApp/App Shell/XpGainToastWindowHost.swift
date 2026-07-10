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

/// Reports the banner's frame in the hosting root view's coordinate space after UIKit layout.
private struct XpGainToastBannerFrameReporter: UIViewRepresentable {
    var onFrameChange: (CGRect) -> Void

    func makeUIView(context: Context) -> XpGainToastBannerFrameReporterView {
        let view = XpGainToastBannerFrameReporterView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateUIView(_ uiView: XpGainToastBannerFrameReporterView, context: Context) {
        uiView.onFrameChange = onFrameChange
        uiView.reportFrameIfNeeded()
    }
}

private final class XpGainToastBannerFrameReporterView: UIView {
    var onFrameChange: ((CGRect) -> Void)?
    private var lastReportedFrame: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportFrameIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportFrameIfNeeded()
    }

    func reportFrameIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let window else { return }
        let frameInWindow = convert(bounds, to: window)
        guard frameInWindow != lastReportedFrame else { return }
        lastReportedFrame = frameInWindow
        onFrameChange?(frameInWindow)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedPresentation: XpGainToastPresentation?

    private var motionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.85)
    }

    private var dismissAnimationDuration: TimeInterval {
        reduceMotion ? 0.2 : 0.4
    }

    private var bannerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let presentation = displayedPresentation {
                XpGainToastBanner(presentation: presentation) {
                    service.dismissManually()
                }
                .padding(.top, 8)
                .overlay {
                    XpGainToastBannerFrameReporter { frame in
                        XpGainToastWindowHost.shared.updateBannerHitFrame(frame)
                    }
                }
                .transition(bannerTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motionAnimation, value: displayedPresentation?.lines.map(\.id))
        .animation(motionAnimation, value: displayedPresentation != nil)
        .onChange(of: service.presentation) { _, newValue in
            syncPresentation(newValue)
        }
        .onAppear {
            syncPresentation(service.presentation)
        }
    }

    private func syncPresentation(_ newValue: XpGainToastPresentation?) {
        if let newValue {
            XpGainToastWindowHost.shared.cancelPendingHide()
            if displayedPresentation == nil {
                withAnimation(motionAnimation) {
                    displayedPresentation = newValue
                }
            } else {
                displayedPresentation = newValue
            }
            return
        }

        guard displayedPresentation != nil else { return }
        withAnimation(motionAnimation) {
            displayedPresentation = nil
        }
        XpGainToastWindowHost.shared.clearBannerDismissTarget()
        XpGainToastWindowHost.shared.scheduleHide(after: dismissAnimationDuration)
    }
}

@MainActor
final class XpGainToastWindowHost {

    static let shared = XpGainToastWindowHost()

    private var window: UIWindow?
    private var boundService: XpGainToastService?
    private var cancellables = Set<AnyCancellable>()
    private var isInstalled = false
    private var bannerDismissButton: UIButton?
    private var pendingHideWorkItem: DispatchWorkItem?

    private init() {}

    func updateBannerHitFrame(_ frame: CGRect) {
        guard let window else { return }
        let button = ensureBannerDismissButton(on: window)
        if frame.isEmpty {
            button.isHidden = true
            return
        }
        button.frame = frame
        button.isHidden = false
        window.bringSubviewToFront(button)
        DispatchQueue.main.async { [weak window, weak button] in
            guard let window, let button, !button.isHidden else { return }
            window.bringSubviewToFront(button)
        }
    }

    func install(service: XpGainToastService) {
        guard !isInstalled else { return }
        isInstalled = true
        boundService = service

        service.$presentation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentation in
                if presentation != nil {
                    self?.cancelPendingHide()
                    self?.show()
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
        cancelPendingHide()
        clearBannerDismissTarget()
        window?.isHidden = true
    }

    private func tearDownWindow() {
        cancelPendingHide()
        clearBannerDismissTarget()
        bannerDismissButton?.removeFromSuperview()
        bannerDismissButton = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func ensureBannerDismissButton(on container: UIWindow) -> UIButton {
        if let bannerDismissButton, bannerDismissButton.superview === container {
            return bannerDismissButton
        }

        bannerDismissButton?.removeFromSuperview()

        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.isAccessibilityElement = false
        button.addAction(
            UIAction { [weak self] _ in
                self?.boundService?.dismissManually()
            },
            for: .touchUpInside
        )
        container.addSubview(button)
        bannerDismissButton = button
        return button
    }

    func scheduleHide(after delay: TimeInterval) {
        pendingHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self?.boundService?.presentation == nil else { return }
            self?.hide()
        }
        pendingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelPendingHide() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
    }

    func clearBannerDismissTarget() {
        bannerDismissButton?.isHidden = true
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
