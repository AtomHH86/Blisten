#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/android-env.sh"

avd_name=abts_api35_x86_64
port="${ABTS_EMULATOR_PORT:-5554}"
timeout="${ABTS_EMULATOR_BOOT_TIMEOUT:-180}"
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 5554 || port > 5682 || port % 2 != 0 )); then
  printf '%s\n' 'ABTS_EMULATOR_PORT must be an even number from 5554 through 5682.' >&2
  exit 2
fi
if [[ ! "$timeout" =~ ^[0-9]+$ ]] || (( timeout < 1 )); then
  printf '%s\n' 'ABTS_EMULATOR_BOOT_TIMEOUT must be a positive number of seconds.' >&2
  exit 2
fi
serial="emulator-$port"
adb="$ANDROID_HOME/platform-tools/adb"
emulator="$ANDROID_HOME/emulator/emulator"
log_dir="$ABTS_TOOLCHAIN_ROOT/emulator-logs"
log_file="$log_dir/$serial.log"
command="${1:-start}"
shift || true
headless=false
if [[ "${1:-}" == --headless && "$command" == start ]]; then
  headless=true
  shift
fi
if (( $# )); then
  printf '%s\n' 'Usage: tool/android-emulator.sh {start [--headless]|status|stop}' >&2
  exit 2
fi
if [[ ! -x "$adb" || ! -x "$emulator" || ! -f "$ANDROID_AVD_HOME/$avd_name.avd/config.ini" ]]; then
  printf '%s\n' 'Run tool/setup-android-emulator.sh first.' >&2
  exit 1
fi

is_connected() { "$adb" -s "$serial" get-state >/dev/null 2>&1; }
check_identity() {
  local actual
  actual="$("$adb" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -n 1)"
  if [[ "$actual" != "$avd_name" ]]; then
    printf '%s belongs to AVD %s, expected %s. Choose another ABTS_EMULATOR_PORT.\n' "$serial" "$actual" "$avd_name" >&2
    return 1
  fi
}

case "$command" in
  start)
    if is_connected; then
      check_identity
    else
      if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        printf 'Emulator port %s is occupied; wait for that emulator or choose another ABTS_EMULATOR_PORT.\n' "$port" >&2
        exit 1
      fi
      mkdir -p "$log_dir"
      printf 'Starting %s; log: %s\n' "$serial" "$log_file" >&2
      emulator_args=(-avd "$avd_name" -port "$port" -accel on -gpu swiftshader -feature -Vulkan -no-boot-anim -no-snapshot)
      if "$headless"; then emulator_args+=(-no-window); fi
      # A separate session keeps the emulator alive after an automation shell exits.
      launched_pid="$(python3 - "$log_file" "$emulator" "${emulator_args[@]}" <<'PY'
import subprocess
import sys
with open(sys.argv[1], 'wb') as log:
    process = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL,
                               stdout=log, stderr=subprocess.STDOUT,
                               start_new_session=True, close_fds=True)
print(process.pid)
PY
)"
    fi
    deadline=$((SECONDS + timeout))
    until [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; do
      if [[ -n "${launched_pid:-}" ]] && ! kill -0 "$launched_pid" 2>/dev/null; then
        printf 'Emulator exited during startup. See %s\n' "$log_file" >&2
        tail -n 20 "$log_file" >&2
        exit 1
      fi
      if (( SECONDS >= deadline )); then
        printf 'Timed out after %s seconds waiting for %s. See %s\n' "$timeout" "$serial" "$log_file" >&2
        exit 1
      fi
      sleep 2
    done
    check_identity
    "$adb" -s "$serial" shell input keyevent KEYCODE_WAKEUP >/dev/null
    "$adb" -s "$serial" shell wm dismiss-keyguard >/dev/null
    printf '%s\n' "$serial"
    ;;
  status)
    is_connected || { printf '%s is not running.\n' "$serial" >&2; exit 1; }
    check_identity
    [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]] || { printf '%s is still booting.\n' "$serial" >&2; exit 1; }
    printf '%s\n' "$serial"
    ;;
  stop)
    if is_connected; then
      check_identity
      "$adb" -s "$serial" emu kill >&2
      deadline=$((SECONDS + 30))
      while lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do
        if (( SECONDS >= deadline )); then
          printf 'Timed out waiting for %s to stop.\n' "$serial" >&2
          exit 1
        fi
        sleep 1
      done
    fi
    ;;
  *) printf '%s\n' 'Usage: tool/android-emulator.sh {start [--headless]|status|stop}' >&2; exit 2 ;;
esac
