#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:?APK path argument is required}"
PACKAGE_NAME="com.nightlink.nightlink"

echo "Checking APK: $APK_PATH"
test -s "$APK_PATH"
ls -lh "$APK_PATH"

echo "Installing NightLink on Android emulator..."
adb install -r "$APK_PATH"

echo "Launching NightLink..."
adb shell am force-stop "$PACKAGE_NAME"
adb shell monkey -p "$PACKAGE_NAME" 1
sleep 20

adb logcat -d -t 3000 > "$RUNNER_TEMP/nightlink-launch-logcat.txt"

if ! adb shell pidof "$PACKAGE_NAME" >/dev/null 2>&1; then
  echo "::error::NightLink process exited after launch."
  echo "Recent fatal/runtime/Flutter log entries:"
  grep -E -i "FATAL EXCEPTION|AndroidRuntime|flutter|NightLink|UnsatisfiedLinkError|ClassNotFoundException|E/flutter" "$RUNNER_TEMP/nightlink-launch-logcat.txt" | tail -250 || true
  echo "Current activity state:"
  adb shell dumpsys activity activities | tail -100 || true
  exit 1
fi

echo "PASS: NightLink stayed running for 20 seconds on Android API 35."
grep -E -i "FATAL EXCEPTION|AndroidRuntime|flutter|NightLink|E/flutter" "$RUNNER_TEMP/nightlink-launch-logcat.txt" | tail -80 || true
