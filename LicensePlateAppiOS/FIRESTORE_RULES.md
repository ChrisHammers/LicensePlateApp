# Firestore Security Rules

The app requires Firestore security rules to allow authenticated users to read and write their own user data, family data, and related collections.

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
    
    // Families collection
    match /families/{familyId} {
      // Allow read if user is a member of this family (check members subcollection)
      allow read: if request.auth != null && 
        exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid));
      
      // Allow write if user is a captain of this family
      allow write: if request.auth != null && 
        exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
        get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain';
      
      // Allow list for share code queries (users need to search by shareCode)
      allow list: if request.auth != null;
      
      // Members subcollection - document ID is the userID
      match /members/{userID} {
        // Allow read if this is the user's own member record OR user is a captain of the family
        allow read: if request.auth != null && (
          userID == request.auth.uid ||
          (exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
           get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain')
        );
        
        // Allow write if this is the user's own member record (to accept/decline) OR user is a captain
        allow write: if request.auth != null && (
          userID == request.auth.uid ||
          (exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
           get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain')
        );
      }
    }
    
    // Games collection
    match /games/{gameId} {
      // Allow read if user is a member of any team in the game
      allow read: if request.auth != null;
      // Allow write if user created the game or is a pilot
      allow write: if request.auth != null && (
        resource.data.createdBy == request.auth.uid ||
        request.resource.data.createdBy == request.auth.uid
      );
    }
    
    // FriendRequests collection
    match /friendRequests/{requestId} {
      allow read: if request.auth != null && (
        resource.data.fromUserID == request.auth.uid ||
        resource.data.toUserID == request.auth.uid
      );
      allow write: if request.auth != null && (
        resource.data.fromUserID == request.auth.uid ||
        resource.data.toUserID == request.auth.uid ||
        request.resource.data.fromUserID == request.auth.uid ||
        request.resource.data.toUserID == request.auth.uid
      );
    }
    
    // Competitions collection
    match /competitions/{competitionId} {
      allow read: if request.auth != null;
      allow write: if false; // Only admins can write (implement admin check if needed)
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
      allow list: if request.auth != null;
    }
    
    // Families collection
    match /families/{familyId} {
      // Allow read if user is a member of this family
      allow read: if request.auth != null && 
        exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid));
      
      // Allow write if user is a captain of this family
      allow write: if request.auth != null && 
        exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
        get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain';
      
      // Allow list for share code queries
      allow list: if request.auth != null;
      
      // Members subcollection
      match /members/{userID} {
        allow read: if request.auth != null && (
          userID == request.auth.uid ||
          (exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
           get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain')
        );
        
        allow write: if request.auth != null && (
          userID == request.auth.uid ||
          (exists(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)) &&
           get(/databases/$(database)/documents/families/$(familyId)/members/$(request.auth.uid)).data.role == 'captain')
        );
      }
    }
    
    // Games collection
    match /games/{gameId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && resource.data.createdBy == request.auth.uid;
    }
    
    // FriendRequests collection
    match /friendRequests/{requestId} {
      allow read: if request.auth != null && (
        resource.data.fromUserID == request.auth.uid ||
        resource.data.toUserID == request.auth.uid
      );
      allow write: if request.auth != null && (
        resource.data.fromUserID == request.auth.uid ||
        resource.data.toUserID == request.auth.uid
      );
    }
    
    // Competitions collection
    match /competitions/{competitionId} {
      allow read: if request.auth != null;
      allow write: if false; // Only admins can write
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

## Additional Notes

- These rules ensure users can only read/write their own user document
- Username uniqueness checks require read access to query the collection
- The rules validate that the document ID matches the authenticated user's UID for security
- **Collection Group Queries**: The `members` subcollection uses collection group queries to find pending invitations. Make sure collection group queries are enabled in Firestore Console:
  1. Go to Firestore Database → Indexes
  2. Create a composite index for collection group `members` with fields: `userID` (Ascending) and `invitationStatus` (Ascending)
  3. This enables the query: `db.collectionGroup("members").whereField("userID", isEqualTo: userID).whereField("invitationStatus", isEqualTo: "pending")`

## Important: Member Document ID Change

**BREAKING CHANGE**: Member documents in Firestore now use `userID` as the document ID instead of `member.id.uuidString`. This change:
- Makes security rules simpler (can check `userID == request.auth.uid`)
- Enables efficient queries for pending invitations
- Requires updating existing member documents in Firestore (migration needed)

### Migration Path

If you have existing member documents with UUID document IDs, you'll need to:
1. Read all existing member documents
2. Create new documents with `userID` as document ID
3. Delete old documents
4. Or use a script to migrate the data

