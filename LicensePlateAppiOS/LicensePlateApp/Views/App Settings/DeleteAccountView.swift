//
//  DeleteAccountView.swift
//  LicensePlateApp
//
//  In-app account deletion flow (App Review Guideline 5.1.1(v); ToS §15,
//  Privacy Policy §11). Renders AccountDeletionViewModel phases only — the
//  server call and local teardown live in services.
//

import SwiftUI
import UIKit

struct DeleteAccountView: View {
    @ObservedObject var authService: FirebaseAuthService
    @StateObject private var viewModel: AccountDeletionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFinalConfirmation = false
    @State private var reauthEmail = ""
    @State private var reauthPassword = ""

    init(authService: FirebaseAuthService) {
        self.authService = authService
        _viewModel = StateObject(wrappedValue: AccountDeletionViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                ScrollView {
                    VStack(spacing: 20) {
                        DeleteAccountExplanationCard()

                        if viewModel.phase == .reauthRequired || viewModel.phase == .reauthenticating {
                            DeleteAccountReauthCard(
                                methods: viewModel.reauthMethods,
                                email: $reauthEmail,
                                password: $reauthPassword,
                                isBusy: viewModel.isBusy,
                                onApple: { viewModel.reauthenticateWithApple() },
                                onGoogle: { startGoogleReauthentication() },
                                onEmailPassword: {
                                    viewModel.reauthenticate(email: reauthEmail, password: reauthPassword)
                                }
                            )
                        } else {
                            confirmationCard
                        }

                        if viewModel.isBusy {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Deleting account…".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Delete Account".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(viewModel.isBusy)
                    .accessibilityHint("Closes the account deletion screen without deleting".localized)
                }
            }
            .interactiveDismissDisabled(viewModel.isBusy)
            .alert("Delete your account?".localized, isPresented: $showFinalConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Delete".localized, role: .destructive) {
                    viewModel.deleteAccountConfirmed()
                }
            } message: {
                Text("This cannot be undone.".localized)
            }
            .alert("Your account has been deleted.".localized, isPresented: completedBinding) {
                Button("OK".localized, role: .cancel) {
                    dismiss()
                }
            }
            .alert("Error".localized, isPresented: errorBinding) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                viewModel.onAppear()
            }
        }
    }

    // MARK: - Confirmation card

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $viewModel.hasAcknowledgedConsequences) {
                Text("I understand my account and data will be permanently deleted".localized)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
            .tint(Color.Theme.primaryBlue)
            .disabled(viewModel.isBusy)
            .accessibilityHint("Required before the delete button becomes available".localized)

            Button {
                showFinalConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)

                    Text("Delete My Account".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.red)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red, lineWidth: 2)
                )
            }
            .disabled(!viewModel.hasAcknowledgedConsequences || viewModel.isBusy)
            .opacity(viewModel.hasAcknowledgedConsequences ? 1 : 0.4)
            .accessibilityLabel("Delete My Account".localized)
            .accessibilityHint("Deletes your account and all synced data after a final confirmation".localized)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    // MARK: - Bindings

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .completed },
            set: { isPresented in
                if !isPresented {
                    dismiss()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    // MARK: - Google re-auth presentation

    private func startGoogleReauthentication() {
        guard let presenter = Self.topViewController() else { return }
        viewModel.reauthenticateWithGoogle(presentingViewController: presenter)
    }

    private static func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController,
           let selected = tabController.selectedViewController {
            return topViewController(controller: selected)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
}

// MARK: - Explanation card (presentational)

struct DeleteAccountExplanationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.red)
                    .accessibilityHidden(true)

                Text("This permanently deletes your account and all synced data.".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
            }

            VStack(alignment: .leading, spacing: 12) {
                DeleteAccountConsequenceRow(
                    icon: "map",
                    text: "Your profile, trips, discoveries, XP, ranks, and achievements will be permanently deleted.".localized
                )
                DeleteAccountConsequenceRow(
                    icon: "shippingbox",
                    text: "Virtual items and unlocks will be lost.".localized
                )
                DeleteAccountConsequenceRow(
                    icon: "creditcard",
                    text: "Purchases and subscriptions do not transfer, and active subscriptions must be canceled separately in your App Store settings.".localized
                )
                DeleteAccountConsequenceRow(
                    icon: "person.2.slash",
                    text: "You will be removed from your friends lists and your family group.".localized
                )
            }

            Text("Some records may be kept where required for legal, security, or fraud prevention, as described in our Privacy Policy.".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }
}

private struct DeleteAccountConsequenceRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Re-authentication card (presentational)

struct DeleteAccountReauthCard: View {
    let methods: [AccountDeletionPolicy.ReauthMethod]
    @Binding var email: String
    @Binding var password: String
    let isBusy: Bool
    let onApple: () -> Void
    let onGoogle: () -> Void
    let onEmailPassword: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityHidden(true)

                Text("For your security, please verify it's you before deleting your account.".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
            }

            ForEach(methods, id: \.self) { method in
                switch method {
                case .apple:
                    reauthProviderButton(
                        title: "Verify with Apple".localized,
                        icon: "applelogo",
                        action: onApple
                    )
                case .google:
                    reauthProviderButton(
                        title: "Verify with Google".localized,
                        icon: "globe",
                        action: onGoogle
                    )
                case .emailPassword:
                    emailPasswordSection
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var emailPasswordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Email".localized, text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)

            SecureField("Password".localized, text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)

            Button {
                onEmailPassword()
            } label: {
                HStack {
                    Text("Verify and Delete Account".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.red)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red, lineWidth: 2)
                )
            }
            .disabled(email.isEmpty || password.isEmpty || isBusy)
            .opacity(email.isEmpty || password.isEmpty ? 0.4 : 1)
            .accessibilityHint("Verifies your password, then deletes your account".localized)
        }
    }

    private func reauthProviderButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.Theme.primaryBlue)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Theme.primaryBlue.opacity(0.1))
            )
        }
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityHint("Verifies your identity, then deletes your account".localized)
    }
}

// MARK: - Previews

#Preview("Delete account — explanation") {
    AppBackgroundView {
        ScrollView {
            VStack(spacing: 20) {
                DeleteAccountExplanationCard()
            }
            .padding(20)
        }
    }
}

#Preview("Delete account — re-auth options") {
    struct ReauthPreviewHost: View {
        @State private var email = ""
        @State private var password = ""

        var body: some View {
            AppBackgroundView {
                ScrollView {
                    VStack(spacing: 20) {
                        DeleteAccountReauthCard(
                            methods: [.apple, .google, .emailPassword],
                            email: $email,
                            password: $password,
                            isBusy: false,
                            onApple: {},
                            onGoogle: {},
                            onEmailPassword: {}
                        )
                    }
                    .padding(20)
                }
            }
        }
    }
    return ReauthPreviewHost()
}

#Preview("Delete account — explanation (dark)") {
    AppBackgroundView {
        ScrollView {
            VStack(spacing: 20) {
                DeleteAccountExplanationCard()
            }
            .padding(20)
        }
    }
    .preferredColorScheme(.dark)
}
