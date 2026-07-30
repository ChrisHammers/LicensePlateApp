//
//  InviteActionLabel.swift
//  LicensePlateApp
//
//  Shared inline spinner + verb for invite send/respond/approve actions.
//

import SwiftUI

/// Action kinds used for in-flight invite UI and ViewModel busy state.
enum InviteBusyKind: Equatable {
    case accept
    case decline
    case cancel
    case send
    case join
    case approve

    var localizedBusyTitle: String {
        switch self {
        case .accept: return "Accepting...".localized
        case .decline: return "Declining...".localized
        case .cancel: return "Canceling...".localized
        case .send: return "Sending...".localized
        case .join: return "Joining...".localized
        case .approve: return "Approving...".localized
        }
    }
}

/// Presentation-only label: idle title, or ProgressView + localized busy verb.
struct InviteActionLabel: View {
    let title: String
    let isBusy: Bool
    let busyTitle: String

    init(title: String, isBusy: Bool, busyKind: InviteBusyKind) {
        self.title = title
        self.isBusy = isBusy
        self.busyTitle = busyKind.localizedBusyTitle
    }

    init(title: String, isBusy: Bool, busyTitle: String) {
        self.title = title
        self.isBusy = isBusy
        self.busyTitle = busyTitle
    }

    var displayedTitle: String {
        isBusy ? busyTitle : title
    }

    var body: some View {
        Group {
            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(busyTitle)
                        .lineLimit(1)
                }
            } else {
                Text(title)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayedTitle)
    }
}

#Preview("Idle") {
    Button {
    } label: {
        InviteActionLabel(title: "Accept".localized, isBusy: false, busyKind: .accept)
            .frame(maxWidth: .infinity)
            .padding()
    }
    .buttonStyle(.borderedProminent)
}

#Preview("Busy") {
    Button {
    } label: {
        InviteActionLabel(title: "Accept".localized, isBusy: true, busyKind: .accept)
            .frame(maxWidth: .infinity)
            .padding()
    }
    .buttonStyle(.borderedProminent)
    .disabled(true)
}
