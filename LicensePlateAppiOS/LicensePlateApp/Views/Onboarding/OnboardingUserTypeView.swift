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
    
    private let currentYear = Calendar.current.component(.year, from: Date())
    
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
                    
                    // Birth year for both user types
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Birth Year")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Picker("Birth Year", selection: Binding(
                            get: { coordinator.birthYear > 0 ? coordinator.birthYear : currentYear - 25 },
                            set: { coordinator.birthYear = $0 }
                        )) {
                            ForEach((currentYear - 100)...currentYear, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                    .padding()
                    .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button("Continue") {
                if coordinator.birthYear == 0 {
                    coordinator.birthYear = currentYear - 25
                }
                onNext()
            }
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.Theme.primaryBlue, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .disabled(selectedType == nil)
            .opacity(selectedType == nil ? 0.6 : 1)
        }
        .onAppear {
            if coordinator.birthYear == 0 {
                coordinator.birthYear = currentYear - 25
            }
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
