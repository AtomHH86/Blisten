#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/android-env.sh"

# Official Google SDK metadata, checked 2026-10-23. Pinned for Intel macOS 13.
# 37.2.12 hung in CoreAudio playback on this host; do not update implicitly.
# https://developer.android.com/studio/emulator_archive
# https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml
avd_name=abts_api35_x86_64
image_package='system-images;android-35;google_apis;x86_64'
avdmanager="$ANDROID_HOME/cmdline-tools/19.0/bin/avdmanager"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
  printf '%s\n' 'This pinned setup targets an Intel Mac; select a matching host package on other systems.' >&2
  exit 1
fi
for prerequisite in "$JAVA_HOME/bin/java" "$avdmanager" "$ANDROID_HOME/platform-tools/adb"; do
  if [[ ! -x "$prerequisite" ]]; then
    printf 'Missing prerequisite: %s\nRestore the local Java 17 / Android command-line toolchain first.\n' "$prerequisite" >&2
    exit 1
  fi
done
if [[ ! -s "$ANDROID_HOME/licenses/android-sdk-license" ]]; then
  printf '%s\n' 'Accept the Android SDK license with sdkmanager --licenses before running this setup.' >&2
  exit 1
fi
mkdir -p "$ABTS_TOOLCHAIN_ROOT/downloads" "$ANDROID_AVD_HOME"

download() {
  local url="$1" checksum="$2" algorithm="${3:-1}" file="$ABTS_TOOLCHAIN_ROOT/downloads/${1##*/}"
  if [[ ! -f "$file" ]] || [[ "$(shasum -a "$algorithm" "$file" | awk '{print $1}')" != "$checksum" ]]; then
    curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$file.part"
    [[ "$(shasum -a "$algorithm" "$file.part" | awk '{print $1}')" == "$checksum" ]] || { printf 'Checksum mismatch: %s\n' "$file.part" >&2; exit 1; }
    mv "$file.part" "$file"
  fi
  printf 'Verified official SHA-%s: %s\n' "$algorithm" "${file##*/}" >&2
}

if [[ ! -f "$ANDROID_HOME/emulator/source.properties" ]]; then
  download 'https://dl.google.com/android/repository/emulator-darwin_x64-15261927.zip' 'e01a07e100568a5dddabff50bd971db7b5ba5a4b87ab4043f9a8e55d6f0e5faf' 256
  unzip -q "$ABTS_TOOLCHAIN_ROOT/downloads/emulator-darwin_x64-15261927.zip" -d "$ANDROID_HOME"
fi
if ! grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*36\.5\.11[[:space:]]*$' "$ANDROID_HOME/emulator/source.properties"; then
  printf '%s\n' 'An emulator other than pinned 36.5.11 is installed; preserve it and choose a separate ABTS_TOOLCHAIN_ROOT.' >&2
  exit 1
fi
# Google archive installation needs the local SDK package registration too.
if [[ ! -f "$ANDROID_HOME/emulator/package.xml" ]]; then
  cat > "$ANDROID_HOME/emulator/package.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<repo:repository xmlns:repo="http://schemas.android.com/repository/android/common/02" xmlns:generic="http://schemas.android.com/repository/android/generic/02" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <localPackage path="emulator" obsolete="false">
    <type-details xsi:type="generic:genericDetailsType"/>
    <revision><major>36</major><minor>5</minor><micro>11</micro></revision>
    <display-name>Android Emulator</display-name>
  </localPackage>
</repo:repository>
XML
fi
image_dir="$ANDROID_HOME/system-images/android-35/google_apis"
if [[ ! -f "$image_dir/x86_64/source.properties" ]]; then
  download 'https://dl.google.com/android/repository/sys-img/google_apis/x86_64-35_r09.zip' '0103e6dab21290c4b9d16550a3ce99476f884eef'
  mkdir -p "$image_dir"
  unzip -q "$ABTS_TOOLCHAIN_ROOT/downloads/x86_64-35_r09.zip" -d "$image_dir"
fi
if ! grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*9[[:space:]]*$' "$image_dir/x86_64/source.properties"; then
  printf '%s\n' 'The existing API 35 image is not validated revision 9.' >&2
  exit 1
fi
if [[ ! -f "$ANDROID_AVD_HOME/$avd_name.avd/config.ini" ]]; then
  printf 'no\n' | "$avdmanager" create avd --name "$avd_name" --package "$image_package" --device pixel_2 --path "$ANDROID_AVD_HOME/$avd_name.avd"
  python3 - "$ANDROID_AVD_HOME/$avd_name.avd/config.ini" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
config = dict(line.split('=', 1) for line in path.read_text().splitlines() if '=' in line)
config.update({
    'hw.ramSize': '2560', 'hw.cpu.ncore': '2', 'vm.heapSize': '256',
    'hw.lcd.width': '720', 'hw.lcd.height': '1280', 'hw.lcd.density': '320',
    'disk.dataPartition.size': '6G', 'hw.gpu.enabled': 'yes', 'hw.gpu.mode': 'swiftshader',
    'hw.audioInput': 'no', 'hw.audioOutput': 'yes', 'hw.keyboard': 'yes',
    'hw.camera.back': 'none', 'hw.camera.front': 'none',
    'showDeviceFrame': 'no', 'skin.name': '720x1280', 'skin.dynamic': 'yes',
})
path.write_text(''.join(f'{key}={value}\n' for key, value in config.items()))
PY
fi
"$ANDROID_HOME/emulator/emulator" -accel-check
printf '\nReady: %s\nStart with: tool/android-emulator.sh start [--headless]\n' "$avd_name"
