#!/usr/bin/env bash
set -Eeuo pipefail

APK_PATH="${1:?APK path argument is required}"
PACKAGE_NAME="com.nightlink.nightlink"
LOG_FILE="${RUNNER_TEMP:-/tmp}/nightlink-launch-logcat.txt"
ACTIVITY_FILE="${RUNNER_TEMP:-/tmp}/nightlink-activity.txt"

diagnostics() {
  status=$?
  echo "::error::NightLink Android smoke test failed (exit code $status)."
  echo "Connected Android devices:"
  adb devices -l || true
  echo "Installed package:"
  adb shell pm path "$PACKAGE_NAME" || true
  echo "NightLink process:"
  adb shell pidof "$PACKAGE_NAME" || true
  echo "Recent activity state:"
  adb shell dumpsys activity activities 2>&1 | tail -120 || true
  echo "Recent Android/Flutter logs:"
  adb logcat -d -t 2500 2>&1 | grep -E -i "FATAL EXCEPTION|AndroidRuntime|E/flutter|flutter|nightlink|UnsatisfiedLinkError|ClassNotFoundException" | tail -200 || true
  exit "$status"
}
trap diagnostics ERR

echo "Checking release APK: $APK_PATH"
test -s "$APK_PATH"
ls -lh "$APK_PATH"

echo "Checking emulator readiness..."
adb wait-for-device
for attempt in $(seq 1 60); do
  booted="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [ "$booted" = "1" ]; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "::error::Android emulator was connected but did not finish booting."
    false
  fi
  sleep 2
done

echo "Installing NightLink..."
adb install -r "$APK_PATH"
adb shell pm path "$PACKAGE_NAME" | grep -q '^package:'

echo "Clearing old logs and launching NightLink..."
adb logcat -c
adb shell am force-stop "$PACKAGE_NAME"
LAUNCH_OUTPUT="$(adb shell am start -W -n "$PACKAGE_NAME/.MainActivity" 2>&1 | tr -d '\r')"
printf '%s\n' "$LAUNCH_OUTPUT"
if ! grep -Fq 'Status: ok' <<< "$LAUNCH_OUTPUT"; then
  echo "::error::Android did not report a successful NightLink activity launch."
  false
fi
echo "Waiting for NightLink process to start..."
APP_PID=""
for attempt in $(seq 1 90); do
  APP_PID="$(adb shell pidof "$PACKAGE_NAME" 2>/dev/null | tr -d '\r' || true)"
  if [ -n "$APP_PID" ]; then
    break
  fi
  sleep 1
done
if [ -z "$APP_PID" ]; then
  echo "::error::NightLink did not create an application process after launch."
  false
fi

echo "NightLink started with PID: $APP_PID"
sleep 30

APP_PID_AFTER="$(adb shell pidof "$PACKAGE_NAME" 2>/dev/null | tr -d '\r' || true)"
if [ -z "$APP_PID_AFTER" ]; then
  echo "::error::NightLink process exited within 30 seconds of launch."
  false
fi

adb shell dumpsys activity activities > "$ACTIVITY_FILE"
if ! grep -Fq "$PACKAGE_NAME" "$ACTIVITY_FILE"; then
  echo "::error::NightLink process is alive, but its activity was not found in ActivityManager."
  tail -120 "$ACTIVITY_FILE" || true
  false
fi

adb logcat -d -t 2500 > "$LOG_FILE"
echo "Recent NightLink launch logs:"
grep -E -i "flutter|nightlink|AndroidRuntime|E/flutter" "$LOG_FILE" | tail -100 || true

if ! python3 - "$LOG_FILE" "$PACKAGE_NAME" <<'PY'
import sys
from pathlib import Path

log_path, package_name = sys.argv[1:]
lines = Path(log_path).read_text(errors="replace").splitlines()
for index, line in enumerate(lines):
    if "FATAL EXCEPTION" not in line:
        continue
    crash = lines[index:index + 25]
    if any(f"Process: {package_name}," in entry for entry in crash):
        print("\n".join(crash))
        raise SystemExit(1)
print(f"No fatal Android exception found for {package_name}.")
PY
then
  echo "::error::NightLink crashed during Android startup."
  false
fi

echo "PASS: NightLink installed, launched, and remained alive with an ActivityManager entry for 30 seconds on Android API 35."
