//
//  TiltMotion.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 6/19/26.
//

//  A reusable gyroscope "tilt / parallax" effect. Apply it to any view —
//  designed for the license card — and it gently rotates in 3D as the phone
//  tilts, with a glare highlight that slides across the surface.
//
//      UserDriversLicenseCard(license: me, style: skin, characterImage: avatar)
//          .tiltEffect()
//
//  Notes:
//  • Neutral (0°) is captured the moment the card appears, so the current
//    holding angle becomes the rest pose and it tilts relative to that.
//  • One shared motion manager is reference-counted across all tilt views,
//    so it's cheap even if several are on screen.
//  • Respects Reduce Motion; stops updates when the view disappears.
//  • There's no gyroscope in the simulator/Previews — pass
//    `simulateWithDrag: true` to drag the card and preview the effect.
//

import SwiftUI
import Combine
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

// MARK: - Shared motion source

final class TiltMotion: ObservableObject {

    static let shared = TiltMotion()

    /// Roll/pitch in radians, relative to the pose captured on first subscribe.
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private var subscribers = 0
    private var baseRoll: Double?
    private var basePitch: Double?
    private let smoothing = 0.18          // low-pass; higher = snappier

    #if canImport(CoreMotion) && os(iOS)
    private let manager = CMMotionManager()
    #endif

    var isAvailable: Bool {
        #if canImport(CoreMotion) && os(iOS)
        return manager.isDeviceMotionAvailable
        #else
        return false
        #endif
    }

    /// Re-zero the rest pose to wherever the device is now.
    func recenter() {
        baseRoll = nil; basePitch = nil
        roll = 0; pitch = 0
    }

    func subscribe() {
        subscribers += 1
        guard subscribers == 1 else { return }
        recenter()
        start()
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 { stop() }
    }

    private func start() {
        #if canImport(CoreMotion) && os(iOS)
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let r = m.attitude.roll, p = m.attitude.pitch
            if self.baseRoll == nil { self.baseRoll = r; self.basePitch = p }
            let dr = r - (self.baseRoll ?? 0)
            let dp = p - (self.basePitch ?? 0)
            self.roll  = self.roll  * (1 - self.smoothing) + dr * self.smoothing
            self.pitch = self.pitch * (1 - self.smoothing) + dp * self.smoothing
        }
        #endif
    }

    private func stop() {
        #if canImport(CoreMotion) && os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
    }
}

// MARK: - Tilt modifier

struct TiltEffect: ViewModifier {

    var maxAngle: Double = 12          // clamp, in degrees
    var gain: Double = 0.9             // how strongly tilt maps to rotation
    var perspective: CGFloat = 0.5
    var glare: Bool = true
    var cornerRadius: CGFloat = 18     // match the card's corner for the glare clip
    var enabled: Bool = true
    var simulateWithDrag: Bool = false // for simulator / previews

    @ObservedObject private var motion = TiltMotion.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragRoll: Double = 0
    @State private var dragPitch: Double = 0

    func body(content: Content) -> some View {
        let active = enabled && !reduceMotion
        let useDrag = simulateWithDrag || !motion.isAvailable

        let rawRoll  = active ? (useDrag ? dragRoll  : motion.roll)  : 0
        let rawPitch = active ? (useDrag ? dragPitch : motion.pitch) : 0
        let yAngle = mapped(rawRoll)
        let xAngle = mapped(rawPitch)

        let tilted = content
            .overlay { if glare && active { glareView(yAngle: yAngle, xAngle: xAngle) } }
            .rotation3DEffect(.degrees(yAngle),  axis: (x: 0, y: 1, z: 0), perspective: perspective)
            .rotation3DEffect(.degrees(-xAngle), axis: (x: 1, y: 0, z: 0), perspective: perspective)

        Group {
            if active && useDrag {
                tilted.gesture(dragGesture)        // drag only attached in sim mode
            } else {
                tilted
            }
        }
        .onAppear  { if active && !useDrag { motion.subscribe() } }
        .onDisappear { if active && !useDrag { motion.unsubscribe() } }
    }

    private func mapped(_ radians: Double) -> Double {
        let deg = radians * 180 / .pi * gain
        return max(-maxAngle, min(maxAngle, deg))
    }

    private func glareView(yAngle: Double, xAngle: Double) -> some View {
        GeometryReader { geo in
            let nx = CGFloat(yAngle / maxAngle)     // -1...1
            let ny = CGFloat(xAngle / maxAngle)
            let intensity = min(1, (nx * nx + ny * ny).squareRoot())
            LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.35), .white.opacity(0.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: geo.size.width * 1.6, height: geo.size.height * 1.6)
                .offset(x: nx * geo.size.width * 0.5, y: ny * geo.size.height * 0.5)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .blendMode(.plusLighter)
                .opacity(0.15 + 0.45 * Double(intensity))
                .allowsHitTesting(false)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                dragRoll  =  Double(v.translation.width)  / 300
                dragPitch = -Double(v.translation.height) / 300
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    dragRoll = 0; dragPitch = 0
                }
            }
    }
}

extension View {
    /// Gently rotates the view in 3D with the device's tilt (gyroscope), with
    /// an optional sliding glare. Rest pose is captured when the view appears.
    /// - Parameter simulateWithDrag: drag to fake tilt where there's no
    ///   gyroscope (simulator / Xcode Previews).
    func tiltEffect(maxAngle: Double = 12,
                    gain: Double = 0.9,
                    perspective: CGFloat = 0.5,
                    glare: Bool = true,
                    cornerRadius: CGFloat = 18,
                    enabled: Bool = true,
                    simulateWithDrag: Bool = false) -> some View {
        modifier(TiltEffect(maxAngle: maxAngle, gain: gain, perspective: perspective,
                            glare: glare, cornerRadius: cornerRadius,
                            enabled: enabled, simulateWithDrag: simulateWithDrag))
    }
}

// MARK: - Preview

private struct TiltAvatar: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.25, blue: 0.85),
                                    Color(red: 0.20, green: 0.45, blue: 0.95)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { g in
                Image(systemName: "figure.wave")
                    .resizable().scaledToFit()
                    .frame(width: g.size.width * 0.55, height: g.size.height * 0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview("Tilt (drag to simulate)") {
    VStack(spacing: 18) {
        Text("Drag the card to simulate tilt.\nOn a real device it follows the gyroscope automatically.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        UserDriversLicenseCard(license: .sample, width: 340, style: .neonNights) { TiltAvatar() }
            .tiltEffect(simulateWithDrag: true)
    }
    .padding()
}
