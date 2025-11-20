# Firebase Storage Security Rules

The app requires Firebase Storage security rules to allow authenticated users to upload and download their own user images.

## Required Security Rules

Add these rules to your Firebase Storage in the Firebase Console:

### For Development (roadtrip-royale-dev)

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // User images - users can upload/read/delete their own images
    match /user_images/{userId}.jpg {
      // Allow read if the user is authenticated and requesting their own image
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Allow write (upload/update) if the user is authenticated and uploading their own image
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // Allow delete if the user is authenticated and deleting their own image
      allow delete: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### For Production (roadtrip-royale-release)

Use the same rules as above, but you may want to add additional restrictions:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // User images - users can upload/read/delete their own images
    match /user_images/{userId}.jpg {
      // Allow read if the user is authenticated and requesting their own image
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Allow write with validation
      allow write: if request.auth != null 
                   && request.auth.uid == userId
                   && request.resource.size < 10 * 1024 * 1024 // 10 MB max
                   && request.resource.contentType.matches('image/.*');
      
      // Allow delete if the user is authenticated and deleting their own image
      allow delete: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## How to Set These Rules

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (`roadtrip-royale-dev` for Debug, `roadtrip-royale-release` for Release)
3. Navigate to **Storage** in the left sidebar
4. Click on the **Rules** tab
5. Paste the appropriate rules above
6. Click **Publish**

## Testing the Rules

After setting the rules, try uploading an image again. The "Object does not exist" error should be resolved if it was a permissions issue.

## Additional Notes

- These rules ensure users can only upload/read/delete their own user images
- The file path must match the user's Firebase UID: `user_images/{userId}.jpg`
- The production rules add file size and content type validation for security

