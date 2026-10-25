#!/usr/bin/env bash
# Wählt das neueste stabile Xcode auf dem macOS-Runner (keine Betas, keine RCs).
set -euo pipefail

candidate=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | grep -viE "beta|release_candidate|_rc" \
  | sort -V \
  | tail -1 || true)

if [[ -z "${candidate}" ]]; then
  echo "Kein versioniertes Xcode gefunden, nutze Standard: $(xcode-select -p)"
else
  echo "Nutze ${candidate}"
  sudo xcode-select -s "${candidate}/Contents/Developer"
fi

xcodebuild -version
xcrun simctl list runtimes | grep -i ios || true
