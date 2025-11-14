//
//  SettingsComponents.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

// MARK: - Setting Toggle Row

/// Reusable setting toggle row with card styling
/// Supports title, description, and optional detail text
struct SettingToggleRow: View {
    let title: String
    let description: String
    let detail: String?
    @Binding var isOn: Bool
    
    init(title: String, description: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self.detail = detail
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                if let detail = detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(Color.Theme.primaryBlue)
                .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

// MARK: - Setting Info Row

/// Reusable text-only info row with card styling
struct SettingInfoRow: View {
    let title: String
    let value: String
    let detail: String?
    
    init(title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
            
            if let detail = detail {
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

// MARK: - Setting Editable Text Row

/// Reusable editable text row with card styling
struct SettingEditableTextRow: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    let detail: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    var isDisabled: Bool = false
    
    @State private var isEditing = false
    @State private var editingValue: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    init(
        title: String,
        value: Binding<String>,
        placeholder: String = "Enter value",
        detail: String? = nil,
        isDisabled: Bool = false,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self._value = value
        self.placeholder = placeholder
        self.detail = detail
        self.isDisabled = isDisabled
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            if isEditing {
                HStack(spacing: 12) {
                    TextField(placeholder, text: $editingValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                        .focused($isTextFieldFocused)
                        .disabled(isDisabled)
                    
                    Button("Save") {
                        value = editingValue
                        isEditing = false
                        onSave()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .disabled(isDisabled)
                    
                    Button("Cancel") {
                        editingValue = value
                        isEditing = false
                        onCancel()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                }
            } else {
                HStack {
                    Text(value)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Spacer()
                    
                    Button {
                        editingValue = value
                        isEditing = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            isTextFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .disabled(isDisabled)
                }
            }
            
            if let detail = detail {
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .onChange(of: value) { oldValue, newValue in
            if !isEditing {
                editingValue = newValue
            }
        }
        .onAppear {
            editingValue = value
        }
    }
}

// MARK: - Setting Share Data Toggle Row

/// Reusable toggle row for shareable data (email, phone, etc.) with optional editing
/// Combines toggle functionality with editable text field
struct SettingShareDataToggleRow: View {
    let title: String
    let value: String?
    let detail: String?
    @Binding var isOn: Bool
    var isEditable: Bool = false
    let onEdit: (() -> Void)?
    
    @State private var isEditing = false
    @State private var editingValue: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    init(
        title: String,
        value: String?,
        detail: String? = nil,
        isOn: Binding<Bool>,
        isEditable: Bool = false,
        onEdit: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self._isOn = isOn
        self.isEditable = isEditable
        self.onEdit = onEdit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and value row
            HStack {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Spacer()
                
                if isEditing {
                    HStack(spacing: 12) {
                        TextField("Enter value", text: $editingValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .rounded))
                            .focused($isTextFieldFocused)
                            .frame(maxWidth: 150)
                        
                        Button("Save") {
                            if let onEdit = onEdit {
                                onEdit()
                            }
                            isEditing = false
                        }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.Theme.primaryBlue)
                        )
                        
                        Button("Cancel") {
                            editingValue = value ?? ""
                            isEditing = false
                        }
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(value != nil && !value!.isEmpty ? value! : "Not set")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                        
                        if isEditable {
                            Button {
                                editingValue = value ?? ""
                                isEditing = true
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                    isTextFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                        }
                    }
                }
            }
            
            // Detail text (if provided) - using .body size
            if let detail = detail {
                Text(detail)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }
            
            // Spacer to push toggle to bottom
            Spacer(minLength: 0)
            
            // Toggle at bottom
            HStack {
                Text(isOn ? "Public - Allows friends to find you" : "Private - Only you can see this")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .tint(Color.Theme.primaryBlue)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .onAppear {
            editingValue = value ?? ""
        }
        .onChange(of: value) { oldValue, newValue in
            if !isEditing {
                editingValue = newValue ?? ""
            }
        }
    }
}

// MARK: - Setting Navigation Row

/// Reusable navigation row with card styling (like Profile button)
struct SettingNavigationRow: View {
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text(description)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

// MARK: - Previews

#Preview("Toggle Row") {
    struct PreviewWrapper: View {
        @State private var isOn = false
        
        var body: some View {
            List {
                SettingToggleRow(
                    title: "Email Privacy",
                    description: "Control who can see your email",
                    detail: "Public - Allows friends to find you",
                    isOn: $isOn
                )
            }
            .listStyle(.insetGrouped)
            .background(Color.Theme.background)
        }
    }
    return PreviewWrapper()
}

#Preview("Info Row") {
    List {
        SettingInfoRow(
            title: "Email",
            value: "user@example.com",
            detail: "Private - Only you can see this"
        )
    }
    .listStyle(.insetGrouped)
    .background(Color.Theme.background)
}

#Preview("Editable Row") {
    struct PreviewWrapper: View {
        @State private var username = "User123"
        
        var body: some View {
            List {
                SettingEditableTextRow(
                    title: "Username",
                    value: $username,
                    placeholder: "Enter username",
                    detail: nil,
                    onSave: { print("Saved: \(username)") },
                    onCancel: { print("Cancelled") }
                )
            }
            .listStyle(.insetGrouped)
            .background(Color.Theme.background)
        }
    }
    return PreviewWrapper()
}

#Preview("Navigation Row") {
    List {
        SettingNavigationRow(
            title: "Profile",
            description: "Edit username and manage account"
        ) {
            print("Navigate to profile")
        }
    }
    .listStyle(.insetGrouped)
    .background(Color.Theme.background)
}

#Preview("Share Data Toggle Row") {
    struct PreviewWrapper: View {
        @State private var isEmailPublic = false
        @State private var isPhonePublic = true
        
        var body: some View {
            List {
                SettingShareDataToggleRow(
                    title: "Email",
                    value: "user@example.com",
                    isOn: $isEmailPublic,
                    isEditable: true
                ) {
                    print("Edit email")
                }
                
                SettingShareDataToggleRow(
                    title: "Phone",
                    value: nil,
                    isOn: $isPhonePublic,
                    isEditable: false
                )
            }
            .listStyle(.insetGrouped)
            .background(Color.Theme.background)
        }
    }
    return PreviewWrapper()
}

