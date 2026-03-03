//
//  ConfirmationDialogView.swift
//  LicensePlateApp
//
//  Reusable confirmation dialog with title, body content, optional checkbox,
//  primary (blue) and secondary buttons. Tap outside to dismiss.
//

import SwiftUI

struct ConfirmationDialogView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    let primaryButtonTitle: String
    let primaryAction: () -> Void
    let secondaryButtonTitle: String
    let secondaryAction: () -> Void
    var optionalCheckbox: (title: String, isChecked: Binding<Bool>)? = nil
    /// Called when user taps outside. If nil, tapping outside does nothing.
    var onTapOutside: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // Semi-transparent background - tap to dismiss (only if onTapOutside provided)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onTapOutside?()
                }
            
            // Dialog box
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Text(title)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    content()
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                
                Divider()
                    .background(Color.Theme.softBrown.opacity(0.2))
                
                VStack(spacing: 16) {
                    if let checkbox = optionalCheckbox {
                        Button {
                            checkbox.isChecked.wrappedValue = !checkbox.isChecked.wrappedValue
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checkbox.isChecked.wrappedValue ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(checkbox.isChecked.wrappedValue ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                                
                                Text(checkbox.title)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                    }
                    
                    // Action buttons: secondary on left, primary on right
                    HStack(spacing: 16) {
                        Button {
                            secondaryAction()
                        } label: {
                            Text(secondaryButtonTitle)
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                        }
                        
                        Button {
                            primaryAction()
                        } label: {
                            Text(primaryButtonTitle)
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.Theme.primaryBlue)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.Theme.cardBackground)
                    .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
        }
        .accessibleTransition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
