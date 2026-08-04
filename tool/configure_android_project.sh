#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f android/app/build.gradle.kts ]]; then
  echo "android/app/build.gradle.kts was not found. Run flutter create first." >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import re

gradle = Path("android/app/build.gradle.kts")
text = gradle.read_text()
text = text.replace(
    "minSdk = flutter.minSdkVersion",
    "minSdk = 24",
)
gradle.write_text(text)

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()
managed_permissions = [
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.BLUETOOTH",
    "android.permission.BLUETOOTH_ADMIN",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.BLUETOOTH_ADVERTISE",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.NEARBY_WIFI_DEVICES",
    "android.permission.ACCESS_LOCAL_NETWORK",
]
for permission in managed_permissions:
    pattern = rf'\s*<uses-permission\b[^>]*android:name="{re.escape(permission)}"[^>]*/>\s*'
    text = re.sub(pattern, "\n", text)

permissions = """    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />
    <uses-permission android:minSdkVersion="29" android:maxSdkVersion="31" android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:minSdkVersion="32" android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:minSdkVersion="37" android:name="android.permission.ACCESS_LOCAL_NETWORK" />
"""
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
text = text.replace(marker, marker + "\n" + permissions, 1)
manifest.write_text(text)
PY
