#!/usr/bin/env bash
# Repeatable computer-only checks. All Android commands target our emulator.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${1:-all}"
case "$suite" in
  all|unit|integration|online) ;;
  -h|--help)
    echo 'Usage: tool/test-android.sh [all|unit|integration|online]'
    echo 'all: analyze + unit/widget tests + dedicated Android emulator tests'
    echo 'online: optional live Bilibili smoke (requires network; separate from all)'
    exit 0
    ;;
  *) echo "Unknown suite: $suite" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo 'Only one suite argument is accepted; physical devices are never selected.' >&2
  exit 2
fi

source "$repo_dir/tool/android-env.sh"
cd "$repo_dir"
run_dir="$repo_dir/build/desktop-tests/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$run_dir"
exec > >(tee "$run_dir/run.log") 2>&1
finish() {
  result=$?
  if [ -n "${device_id:-}" ] && adb -s "$device_id" get-state >/dev/null 2>&1; then
    adb -s "$device_id" shell am force-stop com.bting.audio.debug >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$result" > "$run_dir/exit-code.txt"
  echo "Result: $result; logs: $run_dir"
}
trap finish EXIT

flutter pub get
flutter --version > "$run_dir/flutter-version.txt"
if [ "$suite" = all ] || [ "$suite" = unit ]; then
  flutter analyze --no-pub
  flutter test test --no-pub --reporter expanded
  python3 -B -m unittest discover -s tool/tests -p 'test_apk_packaging.py' -v
fi

if [ "$suite" != unit ]; then
  device_id="$("$repo_dir/tool/android-emulator.sh" start --headless)"
  if [[ ! "$device_id" =~ ^emulator-[0-9]+$ ]] || [ "$(adb -s "$device_id" shell getprop ro.kernel.qemu | tr -d '\r')" != 1 ]; then
    echo "Refusing non-emulator target: $device_id" >&2
    exit 2
  fi
  printf '%s\n' "$device_id" > "$run_dir/device.txt"
  adb -s "$device_id" shell getprop ro.build.version.release > "$run_dir/android-version.txt"
  adb -s "$device_id" shell getprop ro.product.cpu.abi > "$run_dir/abi.txt"
  # Grant runtime permissions once on the dedicated emulator. Flutter's next
  # install preserves these, so tests do not wait on native permission dialogs.
  if [ -z "$(adb -s "$device_id" shell pm path com.bting.audio.debug)" ]; then
    flutter build apk --debug --target-platform android-x64 \
      --target integration_test/audio_modes_test.dart --no-pub
    adb -s "$device_id" install -r -g build/app/outputs/flutter-apk/app-debug.apk
  fi
  adb -s "$device_id" shell pm grant com.bting.audio.debug android.permission.POST_NOTIFICATIONS

  run_integration() {
    # flutter test uninstalls the Android package at completion. The drive
    # adapter with keep-app-running preserves native settings for restart tests.
    flutter drive --driver=test_driver/integration.dart --target="$1" \
      -d "$device_id" --no-pub --keep-app-running --timeout=600 "${@:2}"
    adb -s "$device_id" shell am force-stop com.bting.audio.debug
  }
  if [ "$suite" = online ]; then
    run_integration integration_test/bili_live_test.dart
  else
    run_integration integration_test/audio_modes_test.dart
    run_integration integration_test/restart_test.dart --dart-define=ABTS_RESTART_PHASE=seed
    # run_integration force-stops without uninstalling between these processes.
    run_integration integration_test/restart_test.dart --dart-define=ABTS_RESTART_PHASE=verify
  fi
fi
echo 'Requested checks passed.'
