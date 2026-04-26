# Required Info.plist Entry for QR Code Scanner

Add this entry to your `Info.plist` file to enable camera access for QR code scanning:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan QR codes containing Databricks service principal credentials for quick app configuration.</string>
```

## How to Add in Xcode

### Option 1: Using Property List Editor

1. Open your project in Xcode
2. Select your app target
3. Go to the "Info" tab
4. Click the "+" button to add a new key
5. Type: `Privacy - Camera Usage Description`
6. Set value to: `Camera access is required to scan QR codes containing Databricks service principal credentials for quick app configuration.`

### Option 2: Using Source Code Editor

1. Right-click on `Info.plist` in Xcode
2. Select "Open As" → "Source Code"
3. Add the XML snippet above inside the `<dict>` tags
4. Save the file

### Option 3: Manual Edit

If you're editing Info.plist as a raw file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ... existing keys ... -->
    
    <key>NSCameraUsageDescription</key>
    <string>Camera access is required to scan QR codes containing Databricks service principal credentials for quick app configuration.</string>
    
    <!-- ... more existing keys ... -->
</dict>
</plist>
```

## Testing Permission

After adding the key:

1. Build and run the app
2. Navigate to About → API Credentials → Configure Credentials
3. Tap "Scan QR Code"
4. You should see a permission dialog:
   ```
   "dbxWearables" Would Like to Access the Camera
   
   Camera access is required to scan QR codes containing
   Databricks service principal credentials for quick app
   configuration.
   
   [Don't Allow]  [OK]
   ```
5. Tap "OK" to grant permission

## Checking Current Permission Status

You can check camera permission status in iOS Settings:

**Settings → Privacy & Security → Camera → dbxWearables**

Toggle on/off to test the app's behavior when permission is denied.

## Error Handling

The app handles camera permission states:

- **Not Determined**: Shows permission prompt on first scan
- **Authorized**: Scanner works normally
- **Denied**: Shows error message with instructions to enable in Settings
- **Restricted**: Shows error (parental controls or MDM policy)

## App Store Submission

Apple requires `NSCameraUsageDescription` for any app that accesses the camera. Without this key, your app will be **rejected** during App Store review.

The description should clearly explain:
- ✅ Why you need camera access
- ✅ What you'll use it for
- ✅ How it benefits the user

Our description meets these requirements! 📱
