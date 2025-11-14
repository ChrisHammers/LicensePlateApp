//
//  LicensePlateAppApp.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

@main
struct LicensePlateAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            AppUser.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var authService = FirebaseAuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .task {
                    // Initialize with anonymous sign-in if no user exists
                    if !authService.isAuthenticated {
                        try? await authService.signInAnonymously()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
