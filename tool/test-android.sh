#!/usr/bin/env bash
# Repeatable computer-only checks. All Android commands target our emulator.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${1:-all}"
case "$suite" in
  all|unit|integration|online|lint) ;;
  -h|--help)
    echo 'Usage: tool/test-android.sh [all|unit|integration|online|lint]'
    echo 'all: analyze + unit/widget + Android build/lint + dedicated emulator tests'
    echo 'lint: debug application build and Android native lint only'
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
# Only values validated by this invocation may reach device cleanup.
device_id=''
notification_denial_test=false

# Called before any device mutation, including failure cleanup.
verify_dedicated_device() {
  local serial="$1" actual_avd
  [[ "$serial" =~ ^emulator-[0-9]+$ ]] || return 1
  actual_avd="$(adb -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -n 1)" || return 1
  [[ "$actual_avd" = abts_api35_x86_64 ]] || return 1
  [[ "$(adb -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" = 1 ]]
}
finish() {
  result=$?
  trap - EXIT
  cleanup_result=0
  if [ -n "${device_id:-}" ]; then
    if verify_dedicated_device "$device_id"; then
      # Only this fixed debug package is authorized. Never infer a package/device.
      adb -s "$device_id" shell am force-stop com.bting.audio.debug >/dev/null 2>&1 || cleanup_result=1
      if [ "${notification_denial_test:-false}" = true ]; then
        adb -s "$device_id" shell pm clear-permission-flags com.bting.audio.debug android.permission.POST_NOTIFICATIONS user-set user-fixed >/dev/null 2>&1 || cleanup_result=1
        adb -s "$device_id" shell pm grant com.bting.audio.debug android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || cleanup_result=1
      fi
    else
      echo 'Cleanup refused: dedicated emulator identity is no longer verified.' >&2
      cleanup_result=1
    fi
  fi
  if [ "$cleanup_result" != 0 ]; then
    echo 'Required debug-app cleanup did not complete.' >&2
    if [ "$result" = 0 ]; then result=1; fi
  fi
  printf '%s\n' "$result" > "$run_dir/exit-code.txt"
  echo "Result: $result; logs: $run_dir"
  if [ "$result" = 0 ]; then echo 'Requested checks passed.'; fi
  exit "$result"
}
trap finish EXIT

flutter pub get --enforce-lockfile
flutter --version > "$run_dir/flutter-version.txt"
if [ "$suite" = all ] || [ "$suite" = unit ]; then
  flutter analyze --no-pub
  flutter test test --no-pub --reporter expanded
  python3 -B -m unittest discover -s tool/tests -p 'test_*.py' -v
fi

if [ "$suite" = all ] || [ "$suite" = lint ]; then
  flutter build apk --debug --target-platform android-x64 --no-pub
  (cd android && ./gradlew :app:lintDebug -Ptarget-platform=android-x64)
fi

if [ "$suite" != unit ] && [ "$suite" != lint ]; then
  candidate_device_id="$("$repo_dir/tool/android-emulator.sh" start --headless)"
  if ! verify_dedicated_device "$candidate_device_id"; then
    echo "Refusing target outside the dedicated AVD: $candidate_device_id" >&2
    exit 2
  fi
  # EXIT cleanup receives only a successfully validated serial.
  device_id="$candidate_device_id"
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
    run_integration integration_test/credential_storage_test.dart
    run_integration integration_test/audio_modes_test.dart
    run_integration integration_test/retry_playback_test.dart
    run_integration integration_test/playback_reliability_test.dart
    run_integration integration_test/playback_lifecycle_race_test.dart
    run_integration integration_test/continuous_restart_test.dart --dart-define=ABTS_RESTART_PHASE=seed
    run_integration integration_test/continuous_restart_test.dart --dart-define=ABTS_RESTART_PHASE=verify
    run_integration integration_test/restart_test.dart --dart-define=ABTS_RESTART_PHASE=seed
    # run_integration force-stops without uninstalling between these processes.
    run_integration integration_test/restart_test.dart --dart-define=ABTS_RESTART_PHASE=verify
    run_integration integration_test/cache_cleanup_playback_test.dart
    run_integration integration_test/playback_recovery_test.dart
    run_integration integration_test/audio_focus_playback_test.dart
    run_integration integration_test/task5_timer_integration_test.dart
    run_integration integration_test/task5_settings_lifecycle_test.dart
    run_integration integration_test/task5_detail_cid_native_test.dart
    # This probe verifies a real system broadcast after Activity destruction.
    python3 -B tool/verify-audio-focus-lifetime.py --serial "$device_id" \
      --evidence-dir "$run_dir/audio-focus-lifetime"
    BLISTEN_SCREENSHOT_DIR="$run_dir/panel-screenshots" flutter drive \
      --driver=test_driver/visual.dart --target=integration_test/task5_panels_visual_test.dart \
      -d "$device_id" --no-pub --keep-app-running --timeout=600
    adb -s "$device_id" shell am force-stop com.bting.audio.debug
    # Verify foreground navigation/playback after a real Android permission
    # denial. Fixed flags model a prior denial and prevent a native dialog.
    notification_denial_test=true
    adb -s "$device_id" shell pm revoke com.bting.audio.debug android.permission.POST_NOTIFICATIONS
    adb -s "$device_id" shell pm set-permission-flags com.bting.audio.debug android.permission.POST_NOTIFICATIONS user-set user-fixed
    BLISTEN_SCREENSHOT_DIR="$run_dir/screenshots" flutter drive \
      --driver=test_driver/visual.dart --target=integration_test/visual_design_test.dart \
      -d "$device_id" --no-pub --keep-app-running --timeout=600 \
      --dart-define=BLISTEN_EXPECT_NOTIFICATIONS_DENIED=true
    adb -s "$device_id" shell am force-stop com.bting.audio.debug
  fi
fi
