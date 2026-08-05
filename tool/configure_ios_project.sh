#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ios/Runner/Info.plist ]]; then
  echo "ios/Runner/Info.plist was not found. Run flutter create first." >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import plistlib
import re

info_path = Path("ios/Runner/Info.plist")
with info_path.open("rb") as source:
    info = plistlib.load(source)

info["NSLocalNetworkUsageDescription"] = (
    "MeshTalk discovers and communicates with nearby devices without using the internet."
)
info["NSBluetoothAlwaysUsageDescription"] = (
    "MeshTalk uses Bluetooth to discover and exchange messages with nearby devices."
)
info["NSBluetoothPeripheralUsageDescription"] = (
    "MeshTalk uses Bluetooth to advertise this device to nearby MeshTalk users."
)
bonjour = list(info.get("NSBonjourServices", []))
service = "_meshtalk-chat._tcp"
if service not in bonjour:
    bonjour.append(service)
info["NSBonjourServices"] = sorted(set(bonjour))

with info_path.open("wb") as destination:
    plistlib.dump(info, destination, sort_keys=False)

podfile = Path("ios/Podfile")
if podfile.exists():
    text = podfile.read_text()
    pattern = re.compile(r"^#?\s*platform\s+:ios,\s*'[^']+'", re.MULTILINE)
    replacement = "platform :ios, '13.0'"
    if pattern.search(text):
        text = pattern.sub(replacement, text, count=1)
    else:
        text = replacement + "\n" + text
    podfile.write_text(text)

project = Path("ios/Runner.xcodeproj/project.pbxproj")
if project.exists():
    text = project.read_text()
    text = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
        "IPHONEOS_DEPLOYMENT_TARGET = 13.0;",
        text,
    )
    project.write_text(text)
PY

/usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c 'Print :NSBonjourServices' ios/Runner/Info.plist
