//
//  ChildFamilyPromptBanner.swift
//  LicensePlateApp
//
//  COPPA F-8 banner polish (owner decision) over the F-6 FR-28 surface.
//
//  The restricted-state prompt is PERSISTENT — an unconsented child keeps playing
//  locally and the only way out is a parent adding them to a family — but it must not
//  dominate the home screen. So it introduces itself once at full size, then persists
//  as a compact row. Both presentations sit under the app title (never over it), are
//  entirely tappable, and deep-link to the SAME join-family surface the child gate
//  uses (`JoinFamilySheet` — share-code entry), never a parallel one.
//
//  Deliberately logs NO analytics: an event here would fire only for child sessions on
//  the child's own instance (forbidden by FR-21 / SRS §12).
//

import SwiftUI

struct ChildFamilyPromptBanner: View {
    let presentation: ChildFamilyPromptPresentation
    /// Called after the join surface closes so the host can re-evaluate the prompt.
    var onJoinFamilyDismissed: () -> Void = {}

    @EnvironmentObject private var authService: FirebaseAuthService
    /// The banner OWNS its join sheet. Hoisting it into `ContentView` put a seventh
    /// `.sheet(isPresented:)` on that view's modifier chain, where stacked sheet
    /// modifiers are not reliably honored — the tap silently presented nothing, cutting
    /// off the child's designated route into a family. Every other join entry point
    /// (`ChildAccountGateView`, `FamilyDashboard`) presents it from the view that owns
    /// the trigger; this now matches.
    @State private var isShowingJoinFamily = false

    private var title: String { "child_gate.family_prompt.title".localized }
    private var subtitle: String { "child_gate.family_prompt.subtitle".localized }

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .full:
            promptButton {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleDecorative()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibleDecorative()
                }
                .padding(12)
            }
        case .compact:
            promptButton {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleDecorative()
                    Text(title)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibleDecorative()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func promptButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Button {
            isShowingJoinFamily = true
        } label: {
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: presentation == .compact ? 10 : 12, style: .continuous)
                        .fill(Color.Theme.cardBackground)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            presentation == .full ? "\(title). \(subtitle)" : title
        )
        .accessibilityHint("child_gate.screen.join_button_hint".localized)
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $isShowingJoinFamily) {
            JoinFamilySheet()
                .environmentObject(authService)
                .onDisappear { onJoinFamilyDismissed() }
        }
    }
}

#Preview("Family prompt — full") {
    VStack {
        ChildFamilyPromptBanner(presentation: .full)
        Spacer()
    }
    .padding()
    .environmentObject(FirebaseAuthService())
}

#Preview("Family prompt — compact") {
    VStack {
        ChildFamilyPromptBanner(presentation: .compact)
        Spacer()
    }
    .padding()
    .environmentObject(FirebaseAuthService())
}

#Preview("Family prompt — compact, dark, large text") {
    VStack {
        ChildFamilyPromptBanner(presentation: .compact)
        Spacer()
    }
    .padding()
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
    .environmentObject(FirebaseAuthService())
}
