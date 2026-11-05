#!/usr/bin/env bash
set -Eeuo pipefail

APK_PATH="${1:?APK path argument is required}"
PACKAGE_NAME="com.nightlink.nightlink"
LOG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

collect_diagnostics() {
  status=$?
  trap - ERR
  echo "::error::Android smoke test failed (exit code $status). Collecting emulator diagnostics."
  mkdir -p "$LOG_DIR"
  adb logcat -d -v time > "$LOG_DIR/nightlink-launch-logcat.txt" 2>&1 || true
  adb shell dumpsys activity activities > "$LOG_DIR/nightlink-activity.txt" 2>&1 || true
  adb shell dumpsys package "$PACKAGE_NAME" > "$LOG_DIR/nightlink-package.txt" 2>&1 || true
  echo "Recent fatal/runtime/Flutter errors:"
  grep -E -i "FATAL EXCEPTION|AndroidRuntime|flutter|NightLink|UnsatisfiedLinkError|ClassNotFoundException|E/flutter|Fatal signal" "$LOG_DIR/nightlink-launch-logcat.txt" | tail -200 || true
  echo "Recent activity state:"
  tail -100 "$LOG_DIR/nightlink-activity.txt" || true
  echo "Package state:"
  grep -E "versionName=|versionCode=|codePath=|primaryCpuAbi=|pkgFlags=" "$LOG_DIR/nightlink-package.txt" || true
  exit "$status"
}
trap collect_diagnostics ERR

echo "Checking APK: $APK_PATH"
test -s "$APK_PATH"
ls -lh "$APK_PATH"

SDK_LEVEL="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
if [ "$SDK_LEVEL" != "35" ]; then
  echo "::error::Expected Android 15 / API 35 emulator, got API $SDK_LEVEL."
  exit 1
fi
echo "Confirmed Android API $SDK_LEVEL."

echo "Installing NightLink on Android 15 emulator..."
adb install -r "$APK_PATH"

echo "Verifying installed package..."
PACKAGE_PATH="$(adb shell pm path "$PACKAGE_NAME" | tr -d '\r')"
if [[ "$PACKAGE_PATH" != package:* ]]; then
  echo "::error::Package $PACKAGE_NAME is not installed after adb install."
  exit 1
fi
echo "$PACKAGE_PATH"

echo "Clearing old logcat entries and launching NightLink..."
adb logcat -c
adb shell am force-stop "$PACKAGE_NAME"
adb shell monkey -p "$PACKAGE_NAME" 1

echo "Waiting for NightLink to remain running..."
for attempt in $(seq 1 20); do
  if adb shell pidof "$PACKAGE_NAME" >/dev/null 2>&1; then
    echo "NightLink process is running (check $attempt/20)."
    break
  fi
  if [ "$attempt" -eq 20 ]; then
    echo "::error::NightLink process did not remain alive after launch."
    exit 1
  fi
  sleep 1
done

sleep 10
if ! adb shell pidof "$PACKAGE_NAME" >/dev/null 2>&1; then
  echo "::error::NightLink process exited during the post-launch stability window."
  exit 1
fi

adb logcat -d -v time > "$LOG_DIR/nightlink-launch-logcat.txt"
if grep -E -i "FATAL EXCEPTION|Fatal signal [0-9]+ \(" "$LOG_DIR/nightlink-launch-logcat.txt" | grep -E -i "$PACKAGE_NAME|com\.nightlink" >/dev/null; then
  echo "::error::Fatal application crash detected in logcat."
  exit 1
fi

echo "PASS: NightLink installed and remained running for at least 10 seconds on Android API 35."
echo "APK installation, package registration, launch, and process-stability checks passed."
