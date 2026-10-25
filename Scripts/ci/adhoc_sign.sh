#!/usr/bin/env bash
# Ad-hoc-Signatur mit eingebetteten Berechtigungen.
# SideStore liest die Berechtigungen (HealthKit, App Group) aus dieser Signatur
# und überträgt sie beim Neusignieren mit deiner Apple-ID, soweit erlaubt.
set -euo pipefail

APP="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Eingebettete Frameworks zuerst (gibt es derzeit nicht, Pakete sind statisch gelinkt).
if [[ -d "$APP/Frameworks" ]]; then
  find "$APP/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 \
    | xargs -0 -I{} codesign --force --sign - {}
fi

codesign --force --sign - \
  --entitlements "$ROOT/Widgets/TagwerkWidgets.entitlements" \
  "$APP/PlugIns/TagwerkWidgets.appex"

codesign --force --sign - \
  --entitlements "$ROOT/App/Supporting/Tagwerk.entitlements" \
  "$APP"

echo "Berechtigungen der App:"
codesign -d --entitlements - "$APP" 2>/dev/null || true
echo "Berechtigungen des Widgets:"
codesign -d --entitlements - "$APP/PlugIns/TagwerkWidgets.appex" 2>/dev/null || true
