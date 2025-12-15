# Cloud Function for Family Invitations

## Overview

Instead of allowing clients to directly write to other users' `pendingFamilyInvitations` field, we should use a Cloud Function. This provides:

1. **Better Security**: Validates that the requester is actually a captain
2. **No Broad Permissions**: Clients don't need write access to other users' documents
3. **Centralized Logic**: All invitation management in one place
4. **Audit Trail**: Can log all invitation operations

## Implementation

### Cloud Function Code (TypeScript/JavaScript)

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

/**
 * Add a pending invitation to a user's document
 * Called when a captain invites a user to a family
 */
export const addPendingInvitation = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { invitedUserID, familyFirebaseID, role, invitedBy, invitedAt } = data;

  // Validate input
  if (!invitedUserID || !familyFirebaseID || !role) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  const captainUID = context.auth.uid;

  try {
    // Verify the requester is a captain of the family
    const memberDoc = await admin.firestore()
      .collection('families')
      .doc(familyFirebaseID)
      .collection('members')
      .doc(captainUID)
      .get();

    if (!memberDoc.exists) {
      throw new functions.https.HttpsError('permission-denied', 'User is not a member of this family');
    }

    const memberData = memberDoc.data();
    if (memberData?.role !== 'captain' || !memberData?.isActive) {
      throw new functions.https.HttpsError('permission-denied', 'Only captains can invite members');
    }

    // Get current pending invitations
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(invitedUserID)
      .get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Invited user not found');
    }

    const userData = userDoc.data();
    const pendingInvitations = userData?.pendingFamilyInvitations || [];

    // Check if invitation already exists
    const invitationExists = pendingInvitations.some(
      (inv: any) => inv.familyFirebaseID === familyFirebaseID
    );

    if (invitationExists) {
      return { success: true, message: 'Invitation already exists' };
    }

    // Add new invitation
    // Parse invitedAt - can be ISO string or timestamp
    let invitedAtDate: Date;
    if (typeof invitedAt === 'string') {
      invitedAtDate = new Date(invitedAt);
    } else if (invitedAt) {
      invitedAtDate = new Date(invitedAt);
    } else {
      invitedAtDate = new Date();
    }
    
    const newInvitation = {
      familyFirebaseID,
      role,
      invitedAt: admin.firestore.Timestamp.fromDate(invitedAtDate),
      invitedBy: invitedBy || captainUID
    };

    pendingInvitations.push(newInvitation);

    // Update user document
    await admin.firestore()
      .collection('users')
      .doc(invitedUserID)
      .update({
        pendingFamilyInvitations: pendingInvitations
      });

    return { success: true, message: 'Invitation added successfully' };
  } catch (error: any) {
    console.error('Error adding pending invitation:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', 'Failed to add invitation', error);
  }
});

/**
 * Remove a pending invitation from a user's document
 * Called when:
 * - A captain cancels an invitation
 * - A user accepts/declines an invitation
 */
export const removePendingInvitation = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { userID, familyFirebaseID } = data;

  // Validate input
  if (!userID || !familyFirebaseID) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  const requesterUID = context.auth.uid;

  try {
    // Verify the requester has permission:
    // 1. They are the invited user (can accept/decline their own invitation)
    // 2. OR they are a captain of the family (can cancel invitations)
    const isInvitedUser = requesterUID === userID;

    let isCaptain = false;
    if (!isInvitedUser) {
      const memberDoc = await admin.firestore()
        .collection('families')
        .doc(familyFirebaseID)
        .collection('members')
        .doc(requesterUID)
        .get();

      if (memberDoc.exists) {
        const memberData = memberDoc.data();
        isCaptain = memberData?.role === 'captain' && memberData?.isActive === true;
      }
    }

    if (!isInvitedUser && !isCaptain) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to remove this invitation');
    }

    // Get current pending invitations
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userID)
      .get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();
    const pendingInvitations = userData?.pendingFamilyInvitations || [];

    // Remove invitation
    const updatedInvitations = pendingInvitations.filter(
      (inv: any) => inv.familyFirebaseID !== familyFirebaseID
    );

    // Update user document
    await admin.firestore()
      .collection('users')
      .doc(userID)
      .update({
        pendingFamilyInvitations: updatedInvitations
      });

    return { success: true, message: 'Invitation removed successfully' };
  } catch (error: any) {
    console.error('Error removing pending invitation:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', 'Failed to remove invitation', error);
  }
});
```

### Updated Firestore Rules

```javascript
// Users collection
match /users/{userId} {
  // Allow users to read their own document
  allow read: if request.auth != null && request.auth.uid == userId;
  
  // Allow authenticated users to read other users' documents (for search and lookup)
  allow read: if request.auth != null;
  
  // Allow users to write their own document with validation
  allow create: if request.auth != null 
                && request.auth.uid == userId
                && request.resource.data.id == userId;
  
  // Allow users to update their own document
  // Cloud Functions will handle pendingFamilyInvitations updates
  allow update: if request.auth != null && request.auth.uid == userId;
  
  // Allow authenticated users to query the collection
  allow list: if request.auth != null;
}
```

### Swift Code Changes

Update `FirebaseFamilySyncService.swift`:

```swift
import FirebaseFunctions

/// Add a pending invitation to the user's document via Cloud Function
private func addPendingInvitationToUserDocument(
    userID: String,
    familyFirebaseID: String,
    role: String,
    invitedBy: String?,
    invitedAt: Date
) async {
    guard isOnline else { return }
    
    let functions = Functions.functions()
    let addInvitation = functions.httpsCallable("addPendingInvitation")
    
    do {
        let data: [String: Any] = [
            "invitedUserID": userID,
            "familyFirebaseID": familyFirebaseID,
            "role": role,
            "invitedBy": invitedBy ?? FirebaseAuth.Auth.auth().currentUser?.uid ?? "",
            "invitedAt": Timestamp(date: invitedAt)
        ]
        
        let result = try await addInvitation.call(data)
        print("✅ Added pending invitation via Cloud Function: \(userID)")
    } catch {
        print("⚠️ Error adding pending invitation via Cloud Function: \(error)")
        // Fallback: Could retry or show error to user
    }
}

/// Remove a pending invitation from the user's document via Cloud Function
private func removePendingInvitationFromUserDocument(
    userID: String,
    familyFirebaseID: String
) async {
    guard isOnline else { return }
    
    let functions = Functions.functions()
    let removeInvitation = functions.httpsCallable("removePendingInvitation")
    
    do {
        let data: [String: Any] = [
            "userID": userID,
            "familyFirebaseID": familyFirebaseID
        ]
        
        let result = try await removeInvitation.call(data)
        print("✅ Removed pending invitation via Cloud Function: \(userID)")
    } catch {
        print("⚠️ Error removing pending invitation via Cloud Function: \(error)")
        // Fallback: Could retry or show error to user
    }
}
```

## Deployment

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Initialize Functions: `firebase init functions`
3. Deploy: `firebase deploy --only functions`

## Alternative: Improved Rules (If Keeping Client-Side)

If you prefer to keep it client-side, you can improve the rules to validate captain status:

```javascript
// Users collection
match /users/{userId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null && request.auth.uid == userId;
  
  // Allow update if:
  // 1. User is updating their own document, OR
  // 2. Only pendingFamilyInvitations field is being updated AND
  //    requester is a captain of the family being invited to
  allow update: if request.auth != null && (
    request.auth.uid == userId ||
    (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['pendingFamilyInvitations']) &&
     // Note: This is complex and may not work well in rules
     // Cloud Function is still recommended
     exists(/databases/$(database)/documents/families/$(get(/databases/$(database)/documents/users/$(userId)).data.pendingFamilyInvitations[0].familyFirebaseID)/members/$(request.auth.uid)) &&
     get(/databases/$(database)/documents/families/$(get(/databases/$(database)/documents/users/$(userId)).data.pendingFamilyInvitations[0].familyFirebaseID)/members/$(request.auth.uid)).data.role == 'captain')
  );
}
```

**Note**: The rules-based approach is complex and may not work reliably. Cloud Functions are the recommended approach.

