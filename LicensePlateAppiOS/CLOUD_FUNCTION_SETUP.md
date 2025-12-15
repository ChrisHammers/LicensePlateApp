# Cloud Function Setup Instructions

## Overview

The Swift code has been updated to use Cloud Functions for managing pending family invitations. This provides better security by validating captain permissions server-side.

## What Changed

1. **Swift Code**: Updated `FirebaseFamilySyncService.swift` to call Cloud Functions instead of directly writing to user documents
2. **Firestore Rules**: Removed broad write permission for `pendingFamilyInvitations` field
3. **Cloud Functions**: Need to be deployed (see `CLOUD_FUNCTION_INVITATION.md` for code)

## Required Steps

### 1. Deploy Cloud Functions

Follow the instructions in `CLOUD_FUNCTION_INVITATION.md` to:
- Set up Firebase Functions
- Deploy the `addPendingInvitation` and `removePendingInvitation` functions

### 2. Update Firestore Rules

The rules in `FIRESTORE_RULES.md` have been updated. Deploy them:

```bash
firebase deploy --only firestore:rules
```

Or manually update in Firebase Console:
- Go to Firestore Database → Rules
- Copy the updated rules from `FIRESTORE_RULES.md`
- Click "Publish"

### 3. Verify Swift Code

The Swift code is already updated and will:
- Call `addPendingInvitation` Cloud Function when creating pending invitations
- Call `removePendingInvitation` Cloud Function when removing invitations
- Handle errors gracefully (member document still created/updated even if Cloud Function fails)

## Testing

1. **Test Adding Invitation**:
   - As a captain, invite a user to a family
   - Check that the invitation appears in the user's `pendingFamilyInvitations` array
   - Verify the Cloud Function logs show successful execution

2. **Test Removing Invitation**:
   - As a captain, cancel a pending invitation
   - Or as the invited user, accept/decline the invitation
   - Check that the invitation is removed from the user's `pendingFamilyInvitations` array

3. **Test Error Handling**:
   - If Cloud Functions are not deployed, the member document will still be created/updated
   - The invitation will work via the member document, but won't appear in user's pending list
   - This is acceptable - the system degrades gracefully

## Fallback Behavior

If Cloud Functions are unavailable:
- Member documents are still created/updated in Firestore
- Invitations can still be loaded from member documents (via collection group query)
- The user's `pendingFamilyInvitations` array won't be updated, but this is not critical
- The system continues to function, just without the optimized pending invitations list

## Security Benefits

1. **No Broad Permissions**: Clients no longer need write access to other users' documents
2. **Server-Side Validation**: Cloud Functions validate that the requester is actually a captain
3. **Audit Trail**: All invitation operations can be logged in Cloud Functions
4. **Centralized Logic**: All invitation management logic is in one place

