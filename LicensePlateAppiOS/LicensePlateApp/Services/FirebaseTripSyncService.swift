//
//  FirebaseTripSyncService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Combine
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Sync status for individual trips
enum SyncStatus: String, Codable {
    case synced       // Successfully synced
    case pending      // Waiting to sync
    case syncing      // Currently syncing
    case error        // Sync failed
    case notSynced    // Never synced (local-only)
}

/// Pending change for offline queue
struct PendingChange: Codable {
    let tripId: UUID
    let changeType: ChangeType
    let timestamp: Date
    let tripData: TripData?
    
    enum ChangeType: String, Codable {
        case create
        case update
        case delete
    }
    
    // Simplified trip data for queue storage
    struct TripData: Codable {
        let id: UUID
        let name: String
        let lastUpdated: Date
        // Add other critical fields as needed
    }
}

/// Firebase Trip Sync Service
/// Handles cloud synchronization of trips for authenticated users
@MainActor
class FirebaseTripSyncService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var syncStatus: [UUID: SyncStatus] = [:]
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    @Published var isSyncEnabled: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private var modelContext: ModelContext?
    private var authService: FirebaseAuthService?
    
    // Offline queue
    private var pendingChanges: [PendingChange] = []
    private let pendingChangesKey = "pendingTripChanges"
    
    // Network monitoring
    private var networkCancellable: AnyCancellable?
    private var wasOffline = false
    
    // Retry tracking
    private var retryAttempts: [UUID: Int] = [:]
    private let maxRetryAttempts = 3
    
    // MARK: - Initialization
    
    init(authService: FirebaseAuthService? = nil) {
        self.authService = authService
        loadPendingChanges()
        // Network observation will be set up in initializeSync
    }
    
    // MARK: - Setup
    
    /// Initialize sync service with model context
    func initializeSync(modelContext: ModelContext, authService: FirebaseAuthService) {
        self.modelContext = modelContext
        self.authService = authService
        
        // Setup network observation
        setupNetworkObservation()
        
        // Check if sync should be enabled
        updateSyncEnabled()
        
        // If enabled and online, perform initial sync
        if isSyncEnabled && isOnline {
            Task {
                await performInitialSync()
            }
        }
    }
    
    /// Update sync enabled status based on authentication
    func updateSyncEnabled() {
        guard let authService = authService else {
            isSyncEnabled = false
            return
        }
        
        // Only enable sync for truly authenticated (non-anonymous) users
        isSyncEnabled = authService.isTrulyAuthenticated
    }
    
    // MARK: - Network Status
    
    private var isOnline: Bool {
        authService?.isOnline ?? false
    }
    
    private func setupNetworkObservation() {
        // Use a timer to periodically check network status since isOnline is a computed property
        // Alternatively, we can observe network changes through app lifecycle events
        // For now, we'll check network status when sync operations are attempted
        // Network reconnection will be handled when processOfflineQueue is called
    }
    
    // MARK: - Pending Changes Queue
    
    private func loadPendingChanges() {
        if let data = UserDefaults.standard.data(forKey: pendingChangesKey),
           let changes = try? JSONDecoder().decode([PendingChange].self, from: data) {
            pendingChanges = changes
        }
    }
    
    private func savePendingChanges() {
        if let data = try? JSONEncoder().encode(pendingChanges) {
            UserDefaults.standard.set(data, forKey: pendingChangesKey)
        }
    }
    
    private func addToQueue(tripId: UUID, changeType: PendingChange.ChangeType, trip: Trip? = nil) {
        let tripData: PendingChange.TripData? = trip.map { trip in
            PendingChange.TripData(
                id: trip.id,
                name: trip.name,
                lastUpdated: trip.lastUpdated
            )
        }
        
        let change = PendingChange(
            tripId: tripId,
            changeType: changeType,
            timestamp: Date(),
            tripData: tripData
        )
        
        // Remove any existing pending change for this trip
        pendingChanges.removeAll { $0.tripId == tripId }
        pendingChanges.append(change)
        savePendingChanges()
    }
    
    private func removeFromQueue(tripId: UUID) {
        pendingChanges.removeAll { $0.tripId == tripId }
        savePendingChanges()
    }
    
    // MARK: - Public Sync Methods
    
    /// Handle trip change (create, update, delete)
    func handleTripChange(_ trip: Trip, changeType: PendingChange.ChangeType) {
        guard isSyncEnabled else { return }
        
        // Update lastUpdated if it's an update
        if changeType == .update {
            trip.lastUpdated = Date.now
        }
        
        // Update sync status
        syncStatus[trip.id] = .pending
        
        if isOnline {
            Task {
                await syncTrip(trip, changeType: changeType)
            }
        } else {
            // Add to offline queue
            addToQueue(tripId: trip.id, changeType: changeType, trip: trip)
            wasOffline = true
        }
    }
    
    /// Sync a single trip immediately
    func syncTrip(_ trip: Trip, changeType: PendingChange.ChangeType = .update) async {
        guard isSyncEnabled else { return }
        guard let userId = auth.currentUser?.uid else {
            syncStatus[trip.id] = .error
            return
        }
        
        syncStatus[trip.id] = .syncing
        
        do {
            if changeType == .delete {
                try await deleteTripFromFirestore(trip)
            } else {
                try await uploadTripToFirestore(trip, userId: userId)
            }
            
            syncStatus[trip.id] = .synced
            trip.lastSyncedAt = Date()
            removeFromQueue(tripId: trip.id)
            
            // Save model context
            try? modelContext?.save()
        } catch {
            syncStatus[trip.id] = .error
            syncError = error.localizedDescription
            
            // Add to queue if offline or retryable error
            if !isOnline || shouldRetry(tripId: trip.id) {
                addToQueue(tripId: trip.id, changeType: changeType, trip: trip)
            }
        }
    }
    
    /// Sync all trips
    func syncAllTrips() async {
        guard isSyncEnabled else { return }
        guard let modelContext = modelContext else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            let descriptor = FetchDescriptor<Trip>()
            let trips = try modelContext.fetch(descriptor)
            
            for trip in trips {
                await syncTrip(trip)
            }
            
            lastSyncTime = Date()
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
    
    /// Download trips from Firestore
    func downloadTripsFromFirestore() async {
        guard isSyncEnabled else { return }
        guard let userId = auth.currentUser?.uid else { return }
        guard let modelContext = modelContext else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            let snapshot = try await db.collection("trips")
                .whereField("userId", isEqualTo: userId)
                .order(by: "lastUpdated", descending: true)
                .getDocuments()
            
            let remoteTrips = snapshot.documents.compactMap { doc -> [String: Any]? in
                var data = doc.data()
                data["firestoreId"] = doc.documentID
                return data
            }
            
            // Get local trips
            let descriptor = FetchDescriptor<Trip>()
            let localTrips = try modelContext.fetch(descriptor)
            let localTripsById = Dictionary(uniqueKeysWithValues: localTrips.map { ($0.id, $0) })
            
            // Process remote trips
            for remoteData in remoteTrips {
                guard let remoteIdString = remoteData["id"] as? String,
                      let remoteId = UUID(uuidString: remoteIdString) else {
                    continue
                }
                
                if let localTrip = localTripsById[remoteId] {
                    // Existing trip - resolve conflict
                    await resolveConflict(local: localTrip, remote: remoteData)
                } else {
                    // New trip - download
                    await downloadTripFromFirestore(remoteData, modelContext: modelContext)
                }
            }
            
            lastSyncTime = Date()
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
    
    /// Process offline queue when network becomes available
    func processOfflineQueue() async {
        guard isSyncEnabled else { return }
        guard isOnline else { return }
        
        let changes = pendingChanges
        guard !changes.isEmpty else { return }
        
        pendingChanges.removeAll()
        savePendingChanges()
        
        for change in changes {
            if change.changeType == .delete {
                // Handle delete
                if let trip = findTripById(change.tripId) {
                    await syncTrip(trip, changeType: .delete)
                }
            } else {
                // Handle create/update
                if let trip = findTripById(change.tripId) {
                    await syncTrip(trip, changeType: change.changeType)
                }
            }
        }
        
        // Update wasOffline flag after processing
        wasOffline = false
    }
    
    /// Check network status and process queue if online
    func checkNetworkAndSync() async {
        if isOnline && !pendingChanges.isEmpty {
            await processOfflineQueue()
        }
    }
    
    /// Perform initial sync on app launch/login
    func performInitialSync() async {
        // Download new trips from Firestore
        await downloadTripsFromFirestore()
        
        // Process any pending changes
        await processOfflineQueue()
    }
    
    // MARK: - Private Helper Methods
    
    private func findTripById(_ id: UUID) -> Trip? {
        guard let modelContext = modelContext else { return nil }
        // Fetch all trips and filter by id (SwiftData predicate with UUID can be tricky)
        let descriptor = FetchDescriptor<Trip>()
        guard let trips = try? modelContext.fetch(descriptor) else { return nil }
        return trips.first { $0.id == id }
    }
    
    private func shouldRetry(tripId: UUID) -> Bool {
        let attempts = retryAttempts[tripId] ?? 0
        return attempts < maxRetryAttempts
    }
    
    private func incrementRetry(tripId: UUID) {
        retryAttempts[tripId] = (retryAttempts[tripId] ?? 0) + 1
    }
    
    // MARK: - Firestore Operations
    
    /// Convert Trip to Firestore document data
    private func tripToFirestoreData(_ trip: Trip, userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": trip.id.uuidString,
            "userId": userId,
            "createdAt": Timestamp(date: trip.createdAt),
            "lastUpdated": Timestamp(date: trip.lastUpdated),
            "name": trip.name,
            "skipVoiceConfirmation": trip.skipVoiceConfirmation,
            "holdToTalk": trip.holdToTalk,
            "isTripEnded": trip.isTripEnded,
            "saveLocationWhenMarkingPlates": trip.saveLocationWhenMarkingPlates,
            "showMyLocationOnLargeMap": trip.showMyLocationOnLargeMap,
            "trackMyLocationDuringTrip": trip.trackMyLocationDuringTrip,
            "showMyActiveTripOnLargeMap": trip.showMyActiveTripOnLargeMap,
            "showMyActiveTripOnSmallMap": trip.showMyActiveTripOnSmallMap,
            "enabledCountryStrings": trip.enabledCountryStrings
        ]
        
        // Optional fields
        if let createdBy = trip.createdBy {
            data["createdBy"] = createdBy
        }
        if let startedAt = trip.startedAt {
            data["startedAt"] = Timestamp(date: startedAt)
        }
        if let tripEndedAt = trip.tripEndedAt {
            data["tripEndedAt"] = Timestamp(date: tripEndedAt)
        }
        if let tripEndedBy = trip.tripEndedBy {
            data["tripEndedBy"] = tripEndedBy
        }
        
        // Found regions - encode as array
        data["foundRegions"] = trip.foundRegions.map { region in
            var regionData: [String: Any] = [
                "regionID": region.regionID,
                "foundAt": Timestamp(date: region.foundAt),
                "inputMethod": region.inputMethod.rawValue
            ]
            if let foundBy = region.foundBy {
                regionData["foundBy"] = foundBy
            }
            if let location = region.foundAtLocation {
                regionData["foundAtLocation"] = [
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "altitude": location.altitude,
                    "horizontalAccuracy": location.horizontalAccuracy,
                    "verticalAccuracy": location.verticalAccuracy,
                    "timestamp": Timestamp(date: location.timestamp)
                ]
            }
            return regionData
        }
        
        // Use server timestamp for lastSyncedAt
        data["lastSyncedAt"] = FieldValue.serverTimestamp()
        
        return data
    }
    
    /// Convert Firestore document data to Trip
    private func firestoreDataToTrip(_ data: [String: Any], modelContext: ModelContext) -> Trip? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let lastUpdatedTimestamp = data["lastUpdated"] as? Timestamp else {
            return nil
        }
        
        let createdAt = createdAtTimestamp.dateValue()
        let lastUpdated = lastUpdatedTimestamp.dateValue()
        
        // Parse found regions
        var foundRegions: [FoundRegion] = []
        if let regionsArray = data["foundRegions"] as? [[String: Any]] {
            for regionData in regionsArray {
                guard let regionID = regionData["regionID"] as? String,
                      let foundAtTimestamp = regionData["foundAt"] as? Timestamp,
                      let inputMethodString = regionData["inputMethod"] as? String,
                      let inputMethod = FoundRegion.InputMethod(rawValue: inputMethodString) else {
                    continue
                }
                
                let foundAt = foundAtTimestamp.dateValue()
                let foundBy = regionData["foundBy"] as? String
                
                var locationData: LocationData? = nil
                if let locationDict = regionData["foundAtLocation"] as? [String: Any],
                   let lat = locationDict["latitude"] as? Double,
                   let lon = locationDict["longitude"] as? Double,
                   let alt = locationDict["altitude"] as? Double,
                   let hAcc = locationDict["horizontalAccuracy"] as? Double,
                   let vAcc = locationDict["verticalAccuracy"] as? Double,
                   let timestamp = locationDict["timestamp"] as? Timestamp {
                    locationData = LocationData(
                        latitude: lat,
                        longitude: lon,
                        altitude: alt,
                        horizontalAccuracy: hAcc,
                        verticalAccuracy: vAcc,
                        timestamp: timestamp.dateValue()
                    )
                }
                
                foundRegions.append(FoundRegion(
                    regionID: regionID,
                    foundAt: foundAt,
                    inputMethod: inputMethod,
                    foundBy: foundBy,
                    foundAtLocation: locationData
                ))
            }
        }
        
        // Parse optional fields
        let skipVoiceConfirmation = data["skipVoiceConfirmation"] as? Bool ?? false
        let holdToTalk = data["holdToTalk"] as? Bool ?? true
        let createdBy = data["createdBy"] as? String
        let startedAt = (data["startedAt"] as? Timestamp)?.dateValue()
        let isTripEnded = data["isTripEnded"] as? Bool ?? false
        let tripEndedAt = (data["tripEndedAt"] as? Timestamp)?.dateValue()
        let tripEndedBy = data["tripEndedBy"] as? String
        let saveLocationWhenMarkingPlates = data["saveLocationWhenMarkingPlates"] as? Bool ?? true
        let showMyLocationOnLargeMap = data["showMyLocationOnLargeMap"] as? Bool ?? true
        let trackMyLocationDuringTrip = data["trackMyLocationDuringTrip"] as? Bool ?? true
        let showMyActiveTripOnLargeMap = data["showMyActiveTripOnLargeMap"] as? Bool ?? true
        let showMyActiveTripOnSmallMap = data["showMyActiveTripOnSmallMap"] as? Bool ?? true
        let enabledCountryStrings = data["enabledCountryStrings"] as? String ?? "United States,Canada,Mexico"
        let lastSyncedAt = (data["lastSyncedAt"] as? Timestamp)?.dateValue()
        let firestoreId = data["firestoreId"] as? String
        
        let trip = Trip(
            id: id,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            name: name,
            foundRegions: foundRegions,
            skipVoiceConfirmation: skipVoiceConfirmation,
            holdToTalk: holdToTalk,
            createdBy: createdBy,
            startedAt: startedAt,
            isTripEnded: isTripEnded,
            tripEndedAt: tripEndedAt,
            tripEndedBy: tripEndedBy,
            saveLocationWhenMarkingPlates: saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: trackMyLocationDuringTrip,
            showMyActiveTripOnLargeMap: showMyActiveTripOnLargeMap,
            showMyActiveTripOnSmallMap: showMyActiveTripOnSmallMap,
            enabledCountries: enabledCountryStrings.split(separator: ",").compactMap { 
                PlateRegion.Country(rawValue: $0.trimmingCharacters(in: .whitespaces))
            },
            lastSyncedAt: lastSyncedAt,
            firestoreId: firestoreId
        )
        
        return trip
    }
    
    /// Upload trip to Firestore
    private func uploadTripToFirestore(_ trip: Trip, userId: String) async throws {
        let data = tripToFirestoreData(trip, userId: userId)
        
        // Use firestoreId if exists, otherwise use trip.id as document ID
        let documentId = trip.firestoreId ?? trip.id.uuidString
        let docRef = db.collection("trips").document(documentId)
        
        try await docRef.setData(data)
        
        // Update trip with firestoreId
        trip.firestoreId = documentId
        trip.lastSyncedAt = Date()
    }
    
    /// Download trip from Firestore and create locally
    private func downloadTripFromFirestore(_ data: [String: Any], modelContext: ModelContext) async {
        guard let trip = firestoreDataToTrip(data, modelContext: modelContext) else {
            return
        }
        
        // Check if trip already exists locally - fetch all and filter
        let descriptor = FetchDescriptor<Trip>()
        if let trips = try? modelContext.fetch(descriptor),
           let existingTrip = trips.first(where: { $0.id == trip.id }) {
            // Trip exists, update it
            updateTripFromFirestore(existingTrip, from: data)
        } else {
            // New trip, insert it
            modelContext.insert(trip)
        }
        
        try? modelContext.save()
    }
    
    /// Update existing trip with Firestore data
    private func updateTripFromFirestore(_ trip: Trip, from data: [String: Any]) {
        // Update all fields from Firestore data
        if let name = data["name"] as? String {
            trip.name = name
        }
        if let skipVoiceConfirmation = data["skipVoiceConfirmation"] as? Bool {
            trip.skipVoiceConfirmation = skipVoiceConfirmation
        }
        if let holdToTalk = data["holdToTalk"] as? Bool {
            trip.holdToTalk = holdToTalk
        }
        if let createdBy = data["createdBy"] as? String {
            trip.createdBy = createdBy
        }
        if let startedAt = (data["startedAt"] as? Timestamp)?.dateValue() {
            trip.startedAt = startedAt
        }
        if let isTripEnded = data["isTripEnded"] as? Bool {
            trip.isTripEnded = isTripEnded
        }
        if let tripEndedAt = (data["tripEndedAt"] as? Timestamp)?.dateValue() {
            trip.tripEndedAt = tripEndedAt
        }
        if let tripEndedBy = data["tripEndedBy"] as? String {
            trip.tripEndedBy = tripEndedBy
        }
        if let saveLocationWhenMarkingPlates = data["saveLocationWhenMarkingPlates"] as? Bool {
            trip.saveLocationWhenMarkingPlates = saveLocationWhenMarkingPlates
        }
        if let showMyLocationOnLargeMap = data["showMyLocationOnLargeMap"] as? Bool {
            trip.showMyLocationOnLargeMap = showMyLocationOnLargeMap
        }
        if let trackMyLocationDuringTrip = data["trackMyLocationDuringTrip"] as? Bool {
            trip.trackMyLocationDuringTrip = trackMyLocationDuringTrip
        }
        if let showMyActiveTripOnLargeMap = data["showMyActiveTripOnLargeMap"] as? Bool {
            trip.showMyActiveTripOnLargeMap = showMyActiveTripOnLargeMap
        }
        if let showMyActiveTripOnSmallMap = data["showMyActiveTripOnSmallMap"] as? Bool {
            trip.showMyActiveTripOnSmallMap = showMyActiveTripOnSmallMap
        }
        if let enabledCountryStrings = data["enabledCountryStrings"] as? String {
            trip.enabledCountryStrings = enabledCountryStrings
        }
        if let lastSyncedAt = (data["lastSyncedAt"] as? Timestamp)?.dateValue() {
            trip.lastSyncedAt = lastSyncedAt
        }
        if let firestoreId = data["firestoreId"] as? String {
            trip.firestoreId = firestoreId
        }
        
        // Update found regions
        if let regionsArray = data["foundRegions"] as? [[String: Any]] {
            var foundRegions: [FoundRegion] = []
            for regionData in regionsArray {
                guard let regionID = regionData["regionID"] as? String,
                      let foundAtTimestamp = regionData["foundAt"] as? Timestamp,
                      let inputMethodString = regionData["inputMethod"] as? String,
                      let inputMethod = FoundRegion.InputMethod(rawValue: inputMethodString) else {
                    continue
                }
                
                let foundAt = foundAtTimestamp.dateValue()
                let foundBy = regionData["foundBy"] as? String
                
                var locationData: LocationData? = nil
                if let locationDict = regionData["foundAtLocation"] as? [String: Any],
                   let lat = locationDict["latitude"] as? Double,
                   let lon = locationDict["longitude"] as? Double,
                   let alt = locationDict["altitude"] as? Double,
                   let hAcc = locationDict["horizontalAccuracy"] as? Double,
                   let vAcc = locationDict["verticalAccuracy"] as? Double,
                   let timestamp = locationDict["timestamp"] as? Timestamp {
                    locationData = LocationData(
                        latitude: lat,
                        longitude: lon,
                        altitude: alt,
                        horizontalAccuracy: hAcc,
                        verticalAccuracy: vAcc,
                        timestamp: timestamp.dateValue()
                    )
                }
                
                foundRegions.append(FoundRegion(
                    regionID: regionID,
                    foundAt: foundAt,
                    inputMethod: inputMethod,
                    foundBy: foundBy,
                    foundAtLocation: locationData
                ))
            }
            trip.foundRegions = foundRegions
        }
    }
    
    /// Delete trip from Firestore
    private func deleteTripFromFirestore(_ trip: Trip) async throws {
        guard let firestoreId = trip.firestoreId else {
            // Trip was never synced, nothing to delete
            return
        }
        
        try await db.collection("trips").document(firestoreId).delete()
    }
    
    /// Resolve conflict between local and remote trip (last-write-wins)
    private func resolveConflict(local: Trip, remote: [String: Any]) async {
        guard let remoteLastUpdated = (remote["lastUpdated"] as? Timestamp)?.dateValue() else {
            return
        }
        
        // Compare timestamps
        if remoteLastUpdated > local.lastUpdated {
            // Remote is newer - download and merge
            await downloadTripFromFirestore(remote, modelContext: modelContext!)
            
            // Merge found regions intelligently
            if let remoteRegions = remote["foundRegions"] as? [[String: Any]] {
                mergeFoundRegions(local: local, remoteRegions: remoteRegions)
            }
        } else if local.lastUpdated > remoteLastUpdated {
            // Local is newer - upload to Firestore
            guard let userId = auth.currentUser?.uid else { return }
            do {
                try await uploadTripToFirestore(local, userId: userId)
            } catch {
                syncError = "Failed to sync trip: \(error.localizedDescription)"
            }
        }
        // If equal, no conflict - already synced
    }
    
    /// Merge found regions from remote into local, keeping most recent
    private func mergeFoundRegions(local: Trip, remoteRegions: [[String: Any]]) {
        var mergedRegions: [FoundRegion] = []
        var regionMap: [String: FoundRegion] = [:]
        
        // Add all local regions to map
        for region in local.foundRegions {
            regionMap[region.regionID] = region
        }
        
        // Process remote regions
        for regionData in remoteRegions {
            guard let regionID = regionData["regionID"] as? String,
                  let foundAtTimestamp = regionData["foundAt"] as? Timestamp,
                  let inputMethodString = regionData["inputMethod"] as? String,
                  let inputMethod = FoundRegion.InputMethod(rawValue: inputMethodString) else {
                continue
            }
            
            let foundAt = foundAtTimestamp.dateValue()
            let foundBy = regionData["foundBy"] as? String
            
            var locationData: LocationData? = nil
            if let locationDict = regionData["foundAtLocation"] as? [String: Any],
               let lat = locationDict["latitude"] as? Double,
               let lon = locationDict["longitude"] as? Double,
               let alt = locationDict["altitude"] as? Double,
               let hAcc = locationDict["horizontalAccuracy"] as? Double,
               let vAcc = locationDict["verticalAccuracy"] as? Double,
               let timestamp = locationDict["timestamp"] as? Timestamp {
                locationData = LocationData(
                    latitude: lat,
                    longitude: lon,
                    altitude: alt,
                    horizontalAccuracy: hAcc,
                    verticalAccuracy: vAcc,
                    timestamp: timestamp.dateValue()
                )
            }
            
            let remoteRegion = FoundRegion(
                regionID: regionID,
                foundAt: foundAt,
                inputMethod: inputMethod,
                foundBy: foundBy,
                foundAtLocation: locationData
            )
            
            // If region exists in local, keep the one with later foundAt
            if let localRegion = regionMap[regionID] {
                if remoteRegion.foundAt > localRegion.foundAt {
                    regionMap[regionID] = remoteRegion
                }
            } else {
                // New region, add it
                regionMap[regionID] = remoteRegion
            }
        }
        
        // Update trip with merged regions
        local.foundRegions = Array(regionMap.values)
        local.lastUpdated = Date()
    }
}

