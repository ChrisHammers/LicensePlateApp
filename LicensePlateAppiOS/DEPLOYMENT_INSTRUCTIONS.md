# Firebase Cloud Functions Deployment Instructions

## Files Created

✅ All Firebase Functions files have been created:
- `functions/src/index.ts` - Cloud Functions code
- `functions/package.json` - Node.js dependencies
- `functions/tsconfig.json` - TypeScript configuration
- `functions/.gitignore` - Git ignore rules
- `firebase.json` - Firebase project configuration
- `.firebaserc` - Firebase project aliases (needs your project ID)

## Next Steps

### 1. Configure Firebase Project

Edit `.firebaserc` and replace `"your-project-id-here"` with your actual Firebase project ID:

```json
{
  "projects": {
    "default": "roadtrip-royale-dev"  // or your project ID
  }
}
```

You can find your project ID in:
- Firebase Console → Project Settings → General
- Or in your `GoogleService-Info.plist` files

### 2. Install Firebase CLI (if not already installed)

```bash
npm install -g firebase-tools
```

### 3. Login to Firebase

```bash
firebase login
```

### 4. Build the Functions

```bash
cd functions
npm run build
```

This compiles TypeScript to JavaScript in the `functions/lib/` directory.

### 5. Deploy the Functions

From the project root:

```bash
firebase deploy --only functions
```

Or deploy specific functions:

```bash
firebase deploy --only functions:addPendingInvitation
firebase deploy --only functions:removePendingInvitation
```

### 6. Verify Deployment

After deployment, you should see:
- Function URLs in the output
- Functions listed in Firebase Console → Functions

### 7. Test the Functions

The Swift app will automatically call these functions when:
- A captain invites a user (calls `addPendingInvitation`)
- A captain cancels an invitation or user accepts/declines (calls `removePendingInvitation`)

## Troubleshooting

### Build Errors

If you get TypeScript errors:
```bash
cd functions
npm install
npm run build
```

### Deployment Errors

1. **Authentication**: Make sure you're logged in: `firebase login`
2. **Project ID**: Verify `.firebaserc` has the correct project ID
3. **Permissions**: Ensure you have deploy permissions for the project

### Function Not Found Errors

If the Swift app gets "function not found" errors:
1. Verify functions are deployed: `firebase functions:list`
2. Check function names match exactly: `addPendingInvitation` and `removePendingInvitation`
3. Wait a few minutes after deployment for functions to propagate

## Local Testing (Optional)

You can test functions locally before deploying:

```bash
cd functions
npm run serve
```

This starts the Firebase emulator. The Swift app won't be able to call local functions directly, but you can test them via HTTP or the Firebase Console.

## Monitoring

View function logs:
```bash
firebase functions:log
```

Or in Firebase Console → Functions → Logs

## Security Notes

- Cloud Functions run with admin privileges (can write to any document)
- Functions validate that requesters are captains before allowing operations
- No client-side code can directly write to other users' `pendingFamilyInvitations` field

