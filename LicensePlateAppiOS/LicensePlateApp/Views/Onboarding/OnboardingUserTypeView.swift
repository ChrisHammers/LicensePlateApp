//
//  OnboardingUserTypeView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingUserTypeView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    @State private var selectedType: OnboardingUserType?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text("Are you a Captain or Scout?")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 12) {
                        UserTypeButton(
                            title: "Captain",
                            subtitle: "Parent – create families, manage settings",
                            isSelected: selectedType == .captain
                        ) {
                            selectedType = .captain
                            coordinator.userType = .captain
                        }
                        
                        UserTypeButton(
                            title: "Scout",
                            subtitle: "Child – join an existing family",
                            isSelected: selectedType == .scout
                        ) {
                            selectedType = .scout
                            coordinator.userType = .scout
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button {
                onNext()
            } label: {
                Text("Continue")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .disabled(selectedType == nil)
            .opacity(selectedType == nil ? 0.6 : 1)
        }
    }
}

private struct UserTypeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.Theme.primaryBlue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
