//
//  ForceUpdateView.swift
//  LicensePlateApp
//
//  Hard (blocking) and soft (dismissible) app update surfaces.
//

import SwiftUI
import Combine

enum ForceUpdateMode: Equatable {
    case hard
    case soft
}

@MainActor
final class ForceUpdateViewModel: ObservableObject {
    let mode: ForceUpdateMode
    private let gate: AppUpdateGateService

    init(mode: ForceUpdateMode, gate: AppUpdateGateService) {
        self.mode = mode
        self.gate = gate
    }

    var title: String {
        switch mode {
        case .hard: return "Update Required".localized
        case .soft: return "Update Available".localized
        }
    }

    var message: String {
        switch mode {
        case .hard:
            return "A new version of RoadTrip Royale is required to continue. Please update from the App Store.".localized
        case .soft:
            return "A newer version of RoadTrip Royale is available with improvements and fixes.".localized
        }
    }

    var updateButtonTitle: String { "Update".localized }
    var dismissButtonTitle: String { "Not Now".localized }

    var updateAccessibilityHint: String {
        "Opens the App Store to download the latest version".localized
    }

    var dismissAccessibilityHint: String {
        "Dismisses the update prompt and continues using this version".localized
    }

    func updateTapped() {
        gate.openStore()
    }

    func dismissTapped() {
        gate.dismissSoft()
    }
}

struct ForceUpdateView: View {
    let mode: ForceUpdateMode
    @StateObject private var viewModel: ForceUpdateViewModel
    var onSoftDismissed: (() -> Void)?

    init(mode: ForceUpdateMode, gate: AppUpdateGateService, onSoftDismissed: (() -> Void)? = nil) {
        self.mode = mode
        self.onSoftDismissed = onSoftDismissed
        _viewModel = StateObject(wrappedValue: ForceUpdateViewModel(mode: mode, gate: gate))
    }

    private var combinedAccessibilityLabel: String {
        [viewModel.title, viewModel.message].joined(separator: ". ")
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: mode == .hard ? "exclamationmark.arrow.circlepath" : "arrow.down.app.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibleDecorative()

                Text(viewModel.title)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .multilineTextAlignment(.center)
                    .accessibleHeader(viewModel.title)
                    .supportsDynamicType()

                Text(viewModel.message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .supportsDynamicType()
                    .padding(.horizontal, 8)

                Button {
                    viewModel.updateTapped()
                } label: {
                    HStack {
                        Text(viewModel.updateButtonTitle)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.Theme.primaryBlue)
                    )
                }
                .accessibleButton(
                    label: viewModel.updateButtonTitle,
                    hint: viewModel.updateAccessibilityHint
                )

                if mode == .soft {
                    Button {
                        viewModel.dismissTapped()
                        onSoftDismissed?()
                    } label: {
                        Text(viewModel.dismissButtonTitle)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Theme.softBrown)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .accessibleButton(
                        label: viewModel.dismissButtonTitle,
                        hint: viewModel.dismissAccessibilityHint
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(combinedAccessibilityLabel)
        }
        .interactiveDismissDisabled(mode == .hard)
    }
}

#Preview("Hard gate") {
    ForceUpdateView(mode: .hard, gate: AppUpdateGateService.shared)
}

#Preview("Soft prompt") {
    ForceUpdateView(mode: .soft, gate: AppUpdateGateService.shared)
}
