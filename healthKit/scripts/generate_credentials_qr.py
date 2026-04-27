#!/usr/bin/env python3
"""
Generate a QR code for Databricks service principal credentials.

This script creates a QR code containing the client ID and client secret
in the format expected by the dbxWearables iOS app.

Usage:
    python3 generate_credentials_qr.py

Requirements:
    pip install qrcode[pil]
"""

import json
import qrcode
import sys

def generate_qr_code(client_id: str, client_secret: str, output_file: str = "credentials_qr.png"):
    """
    Generate a QR code containing service principal credentials.
    
    Args:
        client_id: Databricks service principal client ID
        client_secret: Databricks service principal client secret
        output_file: Output filename for the QR code image
    """
    # Create the JSON payload
    credentials = {
        "client_id": client_id,
        "client_secret": client_secret
    }
    
    # Convert to JSON string
    json_string = json.dumps(credentials, separators=(',', ':'))

    # Print a redacted preview only — never log the real client secret to
    # stdout. The QR encoding below still uses the full credentials.
    redacted = {**credentials, "client_secret": "***redacted***"}
    print(f"📋 Credentials JSON ({len(json_string)} bytes, secret redacted in preview):")
    print(json.dumps(redacted, indent=2))
    print()
    
    # Generate QR code
    qr = qrcode.QRCode(
        version=None,  # Auto-detect size
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    
    qr.add_data(json_string)
    qr.make(fit=True)
    
    # Create image
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_file)
    
    print(f"✅ QR code saved to: {output_file}")
    print(f"📱 Scan this QR code in the dbxWearables app to configure credentials")
    print()
    print("🔒 Security reminder:")
    print("   - Keep this QR code secure")
    print("   - Delete after use")
    print("   - Don't commit to version control")
    print("   - Share only via secure channels")


def main():
    print("🔐 Databricks Service Principal QR Code Generator")
    print("=" * 60)
    print()
    
    # Get credentials from user
    client_id = input("Enter Client ID: ").strip()
    if not client_id:
        print("❌ Error: Client ID cannot be empty")
        sys.exit(1)
    
    client_secret = input("Enter Client Secret: ").strip()
    if not client_secret:
        print("❌ Error: Client Secret cannot be empty")
        sys.exit(1)
    
    output_file = input("Output filename (default: credentials_qr.png): ").strip()
    if not output_file:
        output_file = "credentials_qr.png"
    
    print()
    generate_qr_code(client_id, client_secret, output_file)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n❌ Cancelled by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
