# QR Code Credentials Setup

This directory contains scripts for generating QR codes to quickly configure Databricks service principal credentials in the dbxWearables app.

## For Demo Coordinators

### Generating a QR Code

1. **Install Python dependencies:**
   ```bash
   pip install qrcode[pil]
   ```

2. **Run the generator:**
   ```bash
   python3 generate_credentials_qr.py
   ```

3. **Enter your credentials when prompted:**
   ```
   Enter Client ID: abc123-def456-ghi789
   Enter Client Secret: dapi...
   Output filename (default: credentials_qr.png): 
   ```

4. **Share the QR code securely** with Databricks employees who need to demo the app.

### Expected QR Code Format

The QR code contains a JSON object:

```json
{
  "client_id": "your-service-principal-client-id",
  "client_secret": "your-service-principal-client-secret"
}
```

### Security Best Practices

⚠️ **Important Security Considerations:**

- 🔒 **Keep QR codes secure** - They contain sensitive credentials
- 🗑️ **Delete after use** - Don't leave QR code images lying around
- 🚫 **Never commit to Git** - Add `*_qr.png` to `.gitignore`
- 📧 **Share securely** - Use encrypted channels (Slack DM, 1Password, etc.)
- ⏰ **Rotate regularly** - Generate new service principals periodically
- 👥 **Limit distribution** - Only share with authorized Databricks employees

## For App Users (Databricks Employees)

### Scanning a QR Code

1. **Open the dbxWearables app**
2. **Navigate to:** About tab → API Credentials → Configure Credentials
3. **Tap:** "Scan QR Code" button
4. **Grant camera permission** when prompted
5. **Point your camera** at the QR code
6. **Wait for auto-scan** - Credentials will be populated automatically
7. **Confirm and save** - The app will save credentials to Keychain

The entire process takes less than 10 seconds! 🎉

### Camera Permissions

On first scan, iOS will prompt:

```
"dbxWearables" Would Like to Access the Camera
```

Tap **"OK"** to allow scanning. You can manage this later in:
Settings → Privacy & Security → Camera → dbxWearables

### Manual Entry Alternative

If you can't scan the QR code:
1. Tap "Cancel" on the scanner
2. Manually enter the Client ID and Client Secret
3. Tap "Save"

## Troubleshooting

### "Invalid QR code format" Error

**Cause:** QR code doesn't contain valid JSON with `client_id` and `client_secret` fields.

**Solution:** 
- Ensure QR code was generated with the correct script
- Verify the QR code isn't damaged or distorted
- Try manual entry if scanning continues to fail

### "Camera access denied" Error

**Cause:** App doesn't have camera permissions.

**Solution:**
1. Open iOS Settings
2. Scroll to dbxWearables
3. Enable Camera access
4. Return to app and try scanning again

### QR Code Won't Scan

**Troubleshooting steps:**
- ✅ Ensure good lighting
- ✅ Hold phone steady
- ✅ Make sure entire QR code is visible
- ✅ Clean your camera lens
- ✅ Try increasing/decreasing distance
- ✅ Use manual entry as backup

## Technical Details

### QR Code Specifications

- **Format:** JSON string
- **Error Correction:** Medium (15%)
- **Encoding:** UTF-8
- **Expected Size:** ~200-400 bytes (depends on credential length)
- **Recommended QR Version:** Auto-detected (usually version 4-6)

### iOS Implementation

- **Scanner:** AVFoundation AVCaptureSession
- **Metadata Type:** QR Code (.qr)
- **Camera Access:** NSCameraUsageDescription in Info.plist
- **Storage:** iOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

### Data Flow

```
QR Code (JSON) 
  → Camera Scan (AVCaptureSession)
  → JSON Decode (JSONDecoder)
  → Validation (non-empty client_id & client_secret)
  → Populate Fields (SwiftUI State)
  → Auto-Save (Keychain)
  → Success ✅
```

## Examples

### Generate QR for Production

```bash
python3 generate_credentials_qr.py
# Enter: prod-sp-client-id
# Enter: dapi_prod_secret_xyz
# Output: prod_credentials_qr.png
```

### Generate QR for Staging

```bash
python3 generate_credentials_qr.py
# Enter: staging-sp-client-id  
# Enter: dapi_staging_secret_abc
# Output: staging_credentials_qr.png
```

### Multiple Environments

Create separate QR codes for different environments:
- `prod_credentials_qr.png`
- `staging_credentials_qr.png`
- `dev_credentials_qr.png`

Each can be scanned to quickly switch between environments during demos.

## Advanced Usage

### Custom QR Code Styling

Edit `generate_credentials_qr.py` to customize appearance:

```python
# High error correction (for logos/styling)
error_correction=qrcode.constants.ERROR_CORRECT_H

# Larger pixels
box_size=15

# Databricks colors
img = qr.make_image(
    fill_color="#FF3621",  # Databricks Red
    back_color="white"
)
```

### Batch Generation

Create QR codes for multiple service principals:

```python
credentials_list = [
    {"name": "Demo 1", "client_id": "...", "client_secret": "..."},
    {"name": "Demo 2", "client_id": "...", "client_secret": "..."},
]

for cred in credentials_list:
    generate_qr_code(
        cred["client_id"],
        cred["client_secret"],
        f"{cred['name']}_qr.png"
    )
```

---

**Questions?** Contact the dbxWearables development team or your Databricks admin.
