# Google Maps SDK Setup Instructions

## Overview

This app uses Google Maps SDK for iOS to display maps with custom region boundaries. Follow these steps to set up Google Maps in your project.

## Step 1: Add Google Maps SDK

### Using Swift Package Manager (Recommended)

1. Open your Xcode project
2. Go to **File** → **Add Package Dependencies...**
3. Enter the package URL: `https://github.com/googlemaps/ios-maps-sdk`
4. Select the latest version
5. Click **Add Package**

### Using CocoaPods (Alternative)

If you're using CocoaPods, add to your `Podfile`:

```ruby
pod 'GoogleMaps'
```

Then run:
```bash
pod install
```

## Step 2: Get Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Maps SDK for iOS** API
4. Go to **Credentials** → **Create Credentials** → **API Key**
5. Copy your API key

## Step 3: Configure API Key

### Option A: Using Info.plist (Simple)

Add your API key to `Info.plist`:

```xml
<key>GoogleMapsAPIKey</key>
<string>YOUR_API_KEY_HERE</string>
```

### Option B: Using Config File (Recommended for multiple environments)

Create a plist file similar to Firebase config:

**For Debug**: `GoogleMaps-Info-Debug.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>APIKey</key>
    <string>YOUR_DEBUG_API_KEY</string>
</dict>
</plist>
```

**For Release**: `GoogleMaps-Info-Release.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>APIKey</key>
    <string>YOUR_RELEASE_API_KEY</string>
</dict>
</plist>
```

**For both**: `GoogleMaps-Info.plist` (fallback)

Add these files to your Xcode project (same location as `GoogleService-Info.plist`).

## Step 4: Add API Key Restrictions (Security)

In Google Cloud Console:

1. Go to **Credentials** → Select your API key
2. Under **Application restrictions**, select **iOS apps**
3. Add your app's bundle identifier
4. Under **API restrictions**, restrict to **Maps SDK for iOS** (and **Directions API** if you plan to use directions)

## Step 5: Verify Setup

The app will automatically initialize Google Maps on startup. Check the console for:

- ✅ `Google Maps initialized successfully` - Setup is correct
- ⚠️ `Google Maps API key not found` - Check your configuration

## Features Enabled

- **Region Boundaries**: Custom polygons showing state/province boundaries
- **Color Coding**: Regions change color when found (yellow) vs not found (blue)
- **Custom Styling**: Map can be customized for better region visibility
- **Future**: Directions API support (placeholder implemented)

## Troubleshooting

### Maps not displaying

1. Verify API key is correct
2. Check that Maps SDK for iOS is enabled in Google Cloud Console
3. Verify bundle identifier matches API key restrictions
4. Check console for error messages

### Build errors

1. Ensure Google Maps SDK is properly added to your project
2. Clean build folder (Cmd+Shift+K) and rebuild
3. Verify all imports are correct

## Notes

- The app uses approximate region boundaries (simplified polygons)
- Boundaries can be enhanced with more accurate GeoJSON data later
- API key should be kept secure and not committed to version control

