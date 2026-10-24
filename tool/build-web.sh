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
# Flutter tracks output paths as strings. Keep them absolute so an incremental
# build never mistakes the same asset under a relative path for a stale output.
output="$repo_dir/build/web"
if [[ "$mode" = probe ]]; then target=test_driver/web_audio_probe.dart; output="$repo_dir/build/web-probe"; fi
# Avoid stale preview code. No API responses, cookies or audio are cached by a
# service worker. Offline app-shell support is a separate acceptance gate.
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn \
  --target "$target" --output "$output"
for asset in index.html main.dart.js manifest.json assets/FontManifest.json \
  assets/fonts/MaterialIcons-Regular.otf assets/assets/logo.png; do
  if [[ ! -s "$output/$asset" ]]; then
    echo "Incomplete Web build: $asset is missing or empty" >&2
    exit 1
  fi
done
if [[ "$mode" = probe ]]; then
  python3 tool/generate-web-probe-audio.py --output "$output/generated-probe.wav"
fi
printf 'Built %s. Preview locally: python3 tool/serve-web.py --directory %s --port 8768\n' "$mode" "$output"
