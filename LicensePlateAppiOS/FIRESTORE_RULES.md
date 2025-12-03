# Firestore Security Rules

The app requires Firestore security rules to allow authenticated users to read and write their own user data and trip data.

## Required Security Rules

Add these rules to your Firestore database in the Firebase Console:

### For Development (roadtrip-royale-dev)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      // Allow users to read their own document
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Allow users to write their own document (includes create, update, delete)
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // Allow authenticated users to query the collection (for username uniqueness checks)
      // This is needed for the whereField("userName", isEqualTo: username) query
      allow list: if request.auth != null;
    }
    
    // Trips collection - Cloud sync for authenticated users
    match /trips/{tripId} {
      // Allow users to read their own trips
      allow read: if request.auth != null && request.auth.uid == resource.data.userId;
      
      // Allow users to create trips with their own userId
      allow create: if request.auth != null 
                    && request.auth.uid == request.resource.data.userId;
      
      // Allow users to update their own trips
      allow update: if request.auth != null 
                    && request.auth.uid == resource.data.userId
                    && request.auth.uid == request.resource.data.userId;
      
      // Allow users to delete their own trips
      allow delete: if request.auth != null 
                    && request.auth.uid == resource.data.userId;
      
      // Allow users to list their own trips
      allow list: if request.auth != null 
                  && request.query.limit <= 100;
    }
  }
}
```

### For Production (roadtrip-royale-release)

Use the same rules as above, but you may want to add additional restrictions:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      // Allow users to read their own document
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Allow users to write their own document with validation
      allow write: if request.auth != null 
                   && request.auth.uid == userId
                   && request.resource.data.id == userId;
      
      // Allow authenticated users to query the collection (for username uniqueness checks)
      // This is needed for the whereField("userName", isEqualTo: username) query
      allow list: if request.auth != null;
    }
    
    // Trips collection - Cloud sync for authenticated users
    match /trips/{tripId} {
      // Allow users to read their own trips
      allow read: if request.auth != null && request.auth.uid == resource.data.userId;
      
      // Allow users to create trips with their own userId
      allow create: if request.auth != null 
                    && request.auth.uid == request.resource.data.userId;
      
      // Allow users to update their own trips
      allow update: if request.auth != null 
                    && request.auth.uid == resource.data.userId
                    && request.auth.uid == request.resource.data.userId;
      
      // Allow users to delete their own trips
      allow delete: if request.auth != null 
                    && request.auth.uid == resource.data.userId;
      
      // Allow users to list their own trips
      allow list: if request.auth != null 
                  && request.query.limit <= 100;
    }
  }
}
```

## How to Set These Rules

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (`roadtrip-royale-dev` for Debug, `roadtrip-royale-release` for Release)
3. Navigate to **Firestore Database** in the left sidebar
4. Click on the **Rules** tab
5. Paste the appropriate rules above
6. Click **Publish**

## Testing the Rules

After setting the rules, try creating an account again. The permission error should be resolved.

## Firestore Collection Structure

### Trips Collection (`trips/{tripId}`)

Each trip document contains:
- `id`: String (UUID as string)
- `userId`: String (Firebase UID of trip owner)
- `createdAt`: Timestamp
- `lastUpdated`: Timestamp
- `lastSyncedAt`: Timestamp (server timestamp)
- `name`: String
- `foundRegions`: Array<FoundRegion> (Codable struct)
- `skipVoiceConfirmation`: Boolean
- `holdToTalk`: Boolean
- `createdBy`: String? (User ID of trip creator)
- `startedAt`: Timestamp?
- `isTripEnded`: Boolean
- `tripEndedAt`: Timestamp?
- `tripEndedBy`: String? (User ID who ended the trip)
- `saveLocationWhenMarkingPlates`: Boolean
- `showMyLocationOnLargeMap`: Boolean
- `trackMyLocationDuringTrip`: Boolean
- `showMyActiveTripOnLargeMap`: Boolean
- `showMyActiveTripOnSmallMap`: Boolean
- `enabledCountryStrings`: String (comma-separated)

### Firestore Indexes

Create a composite index for efficient queries:
- Collection: `trips`
- Fields: `userId` (Ascending), `lastUpdated` (Descending)
- Query scope: Collection

This index is required for querying trips by user with sorting by lastUpdated.

## Additional Notes

- These rules ensure users can only read/write their own user and trip documents
- Username uniqueness checks require read access to query the collection
- The rules validate that the document ID matches the authenticated user's UID for security
- Trip sync is only available for authenticated (non-anonymous) users

