# Firestore Security Rules

The app requires Firestore security rules to allow authenticated users to read and write their own user data.

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

