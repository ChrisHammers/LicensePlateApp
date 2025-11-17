//
//  ContentView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var path: [UUID] = []
    @State private var isShowingCreateSheet = false
    @State private var isShowingSettings = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

  init() {
    UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: Color.Theme.primaryBlue.uiColor]

     }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                List {
                    Section {
                        header
                            .listRowInsets(.init(top: 24, leading: 20, bottom: 24, trailing: 20))
                            .listRowBackground(Color.clear)
                    }
                    .textCase(nil)

                    if trips.isEmpty {
                        Section {
                            emptyState
                                .listRowInsets(.init(top: 0, leading: 20, bottom: 24, trailing: 20))
                                .listRowBackground(Color.clear)
                        }
                        .textCase(nil)
                    } else {
                        Section("Previous Trips") {
                            tripList
                        }
                        .textCase(nil)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("RoadTrip Royale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                DefaultSettingsView()
            }
            .overlay(alignment: .bottomTrailing) {
                addTripButton
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                NewTripNameSheet { name in
                    createTrip(named: name)
                }
                .presentationDetents([.medium])
            }
            .navigationDestination(for: UUID.self) { tripID in
                if let trip = trips.first(where: { $0.id == tripID }) {
                    TripTrackerView(trip: trip)
                } else {
                    TripMissingView()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RoadTrip Royale")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .shadow(color: Color.Theme.primaryBlue.opacity(0.5), radius: 5)
            
            Text("Spot license plates, conquer the map, and rule the open road!")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.8))

            Text("Track every plate you see across the United States, Canada, and Mexico.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.Theme.accentYellow)

            Text("No trips yet")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Start your first adventure and begin collecting plates from across North America.")
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var tripList: some View {
        ForEach(trips) { trip in
            NavigationLink(value: trip.id) {
                TripRow(trip: trip)
                    .padding(.vertical, 8)
            }
            .listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.clear)
        }
        .onDelete(perform: deleteTrips)
    }

    private var addTripButton: some View {
        Button {
            isShowingCreateSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                Text("Create Trip")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.Theme.primaryBlue)
            )
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 32)
    }

    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    
    private func createTrip(named name: String?) {
        let finalName: String
        let createdAt = Date()

        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalName = dateFormatter.string(from: createdAt)
        }

        let newTrip = Trip(
            createdAt: createdAt,
            name: finalName,
            foundRegions: [],
            skipVoiceConfirmation: defaultSkipVoiceConfirmation,
            holdToTalk: defaultHoldToTalk
        )

        modelContext.insert(newTrip)

        do {
            try modelContext.save()
        } catch {
            // In a production app, handle the error appropriately.
            assertionFailure("Failed to save new trip: \(error)")
        }

        path.append(newTrip.id)
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to delete trip: \(error)")
        }
    }
}

private struct NewTripNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tripName: String = ""
    var onCreate: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Name") {
                    TextField("Automatically use date & time", text: $tripName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(tripName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trip.name)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer()

              Label("\(trip.foundRegionIDs.count)/\(PlateRegion.all.count)", systemImage: "scope")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.accentYellow)
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))

            HStack {
                Label("Started", systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)

                Spacer()

                Text(dateFormatter.string(from: trip.createdAt))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
    }
}

private struct TripMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.Theme.accentYellow)
            Text("Trip Unavailable")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("We could not find the trip you were looking for.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.background)
    }
}

// Default Settings View for new trips
private struct DefaultSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    
    enum SettingsSection: String, CaseIterable {
        case voice = "Voice"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    ForEach(SettingsSection.allCases, id: \.id) { section in
                        Section {
                            switch section {
                            case .voice:
                                voiceSettings
                            }
                        } header: {
                            Text(section.rawValue)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                        .textCase(nil)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
        .background(Color.Theme.background)
    }
    
    private var voiceSettings: some View {
        Group {
            DefaultSettingToggleRow(
                title: "Skip Confirmation",
                description: "Automatically add license plates without confirmation when using Voice. This is the default for NEW trips.",
                isOn: $defaultSkipVoiceConfirmation
            )
            
            DefaultSettingToggleRow(
                title: "Hold to Talk",
                description: "Press and hold the microphone button to record. If disabled the system will listen until you hit stop. This is the default for NEW trips.",
                isOn: $defaultHoldToTalk
            )
        }
    }
}

// Reusable setting toggle row with card styling for default settings
private struct DefaultSettingToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
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

#Preview {
    ContentView()
        .modelContainer(for: Trip.self, inMemory: true)
}
