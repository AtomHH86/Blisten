#!/usr/bin/env bash
# Build the shared application or an isolated, generated-audio browser probe.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-app}"
case "$mode" in app|probe) ;; *) echo 'Usage: tool/build-web.sh [app|probe]' >&2; exit 2;; esac
[[ $# -le 1 ]] || exit 2
if ! command -v flutter >/dev/null 2>&1; then source "$repo_dir/tool/android-env.sh"; fi
cd "$repo_dir"
flutter pub get --enforce-lockfile
target=lib/main.dart
output=build/web
if [[ "$mode" = probe ]]; then target=test_driver/web_audio_probe.dart; output=build/web-probe; fi
# Avoid stale preview code. No API responses, cookies or audio are cached by a
# service worker. Offline app-shell support is a separate acceptance gate.
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn \
  --target "$target" --output "$output"
if [[ "$mode" = probe ]]; then
  python3 tool/generate-web-probe-audio.py --output "$output/generated-probe.wav"
fi
printf 'Built %s. Preview locally: python3 -m http.server 8768 --bind 127.0.0.1 --directory %s\n' "$mode" "$output"
