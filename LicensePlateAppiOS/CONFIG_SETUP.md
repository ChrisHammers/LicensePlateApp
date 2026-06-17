# Firebase and local configuration setup

Private config files are **gitignored**. Copy the committed `.example.plist` templates, then replace placeholders with values from the Firebase Console. **Do not commit** real API keys or `GoogleService-Info*.plist` files.

## Firebase projects

| Build | Plist file | Firebase `PROJECT_ID` |
|-------|------------|------------------------|
| Debug | `LicensePlateApp/GoogleService-Info-Debug.plist` | `roadtrip-royale-dev-d2652` |
| Release / TestFlight | `LicensePlateApp/GoogleService-Info-Release.plist` | `roadtrip-royale-b694d` |

The bare id `roadtrip-royale` (no suffix) is **not** valid for Release builds.

## First-time setup

1. Copy examples (from `LicensePlateAppiOS/`):

   ```bash
   cp LicensePlateApp/GoogleService-Info-Debug.example.plist LicensePlateApp/GoogleService-Info-Debug.plist
   cp LicensePlateApp/GoogleService-Info-Release.example.plist LicensePlateApp/GoogleService-Info-Release.plist
   ```

2. **Debug:** Firebase Console → project `roadtrip-royale-dev-d2652` → your iOS app → download `GoogleService-Info.plist` and replace `GoogleService-Info-Debug.plist` (or paste keys into the copied file).

3. **Release:** Firebase Console → project `roadtrip-royale-b694d` → your iOS app → download `GoogleService-Info.plist` and save as `GoogleService-Info-Release.plist`. The file must include `CLIENT_ID` (required for Google Sign-In).

4. Optional generic fallback for Debug only: `GoogleService-Info.plist` (dev project), also gitignored.

## Verify locally

```bash
plutil -extract PROJECT_ID raw LicensePlateApp/GoogleService-Info-Debug.plist
# expect: roadtrip-royale-dev-d2652

plutil -extract PROJECT_ID raw LicensePlateApp/GoogleService-Info-Release.plist
# expect: roadtrip-royale-b694d

plutil -extract CLIENT_ID raw LicensePlateApp/GoogleService-Info-Release.plist
# must succeed (non-empty CLIENT_ID)
```

## Release build enforcement

The Xcode run script **Validate Firebase Release Config** runs on **Release** builds only. It fails the build if:

- `GoogleService-Info-Release.plist` is missing
- `PROJECT_ID` is not `roadtrip-royale-b694d`
- `CLIENT_ID` is missing

Debug builds are not gated by this script.

At runtime, **Release** loads only `GoogleService-Info-Release` (no fallback to the dev generic plist). **Debug** still may fall back to `GoogleService-Info.plist`.

## Firebase CLI (`.firebaserc`)

- Default / dev: `roadtrip-royale-dev-d2652`
- Production alias: `roadtrip-royale-b694d` (`production`, `RTR Prod`)

Example: `firebase use production` before deploying rules/functions to prod.

## Other gitignored config (out of scope here)

- `LicensePlateApp/RevenueCat-Info.plist`
- `LicensePlateApp/GoogleMaps-Info-Debug.plist`, `GoogleMaps-Info-Release.plist`, `GoogleMaps-Info.plist`

## Manual QA checklist

- [ ] Debug run: app uses dev Firebase (`roadtrip-royale-dev-d2652`)
- [ ] Release archive: succeeds only with valid Release plist
- [ ] Release archive: fails with missing plist, wrong `PROJECT_ID`, or missing `CLIENT_ID`
- [ ] TestFlight build: data and auth hit `roadtrip-royale-b694d`
- [ ] Google Sign-In works on Release
- [ ] App Check (App Attest) and Crashlytics symbols for Release
