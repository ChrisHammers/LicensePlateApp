//
//  CreateFamilySheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct CreateFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel = CreateFamilyViewModel()

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    Section {
                        TextField("Family Name".localized, text: $viewModel.familyName)
                            .textInputAutocapitalization(.words)
                            .disabled(viewModel.isCreating)
                            .accessibleTextField(
                                label: "Family Name".localized,
                                hint: "Choose a name for your family group".localized,
                                value: viewModel.familyName
                            )
                    } header: {
                        Text("Family Name".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    } footer: {
                        Text("Choose a name for your family group".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .listRowBackground(Color.Theme.cardBackground)

                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.caption, design: .rounded))
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .disabled(viewModel.isCreating)

                if viewModel.isCreating {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.Theme.primaryBlue)

                        Text("Creating family...".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .padding(24)
                    .background(Color.Theme.background)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Creating family...".localized)
                }
            }
            .navigationTitle("Create Family".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create".localized) {
                        viewModel.createFamily()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(
                        viewModel.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isCreating
                            || !authService.isOnline
                    )
                }
            }
            .alert("Error".localized, isPresented: $viewModel.showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                viewModel.configure(authService: authService, modelContext: modelContext)
                viewModel.onAppear()
            }
            .onChange(of: viewModel.didCreateSuccessfully) { _, didCreate in
                if didCreate { dismiss() }
            }
        }
    }
}

#Preview {
    CreateFamilySheet()
        .environmentObject(FirebaseAuthService())
}
