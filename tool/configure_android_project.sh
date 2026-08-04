#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f android/app/build.gradle.kts ]]; then
  echo "android/app/build.gradle.kts was not found. Run flutter create first." >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

gradle = Path("android/app/build.gradle.kts")
text = gradle.read_text()
text = text.replace(
    "minSdk = flutter.minSdkVersion",
    "minSdk = 24",
)
gradle.write_text(text)

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()
permissions = """    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
"""
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if "android.permission.BLUETOOTH_SCAN" not in text:
    text = text.replace(marker, marker + "\n" + permissions)
manifest.write_text(text)
PY
