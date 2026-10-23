#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash tool/build-android-apks.sh [--output NEW_DIRECTORY] [--certificate-sha256 HEX]

Build and validate arm64-v8a, armeabi-v7a, x86_64 and universal release APKs.
Requires android/key.properties and its release keystore. Never falls back to
debug signing. The four packages use the pubspec version and the same versionCode.
Default output: dist/v<VERSION>+<BUILD>. Existing output directories are rejected.
Provide the original release certificate SHA-256 to verify upgrade signing identity.
No upload or installation is performed.
EOF
}

output=''
certificate=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output|--certificate-sha256)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage >&2; exit 2; fi
      if [ "$1" = '--output' ]; then output="$2"; else certificate="$2"; fi
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
# shellcheck source=android-env.sh
source "$repo/tool/android-env.sh"
python3 "$repo/tool/apk-metadata.py" --check-release-key "$repo/android/key.properties"

read -r version build_number < <(python3 - <<'PY'
from pathlib import Path
import re
import sys
version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', Path('pubspec.yaml').read_text(), re.M)
meta = re.search(r"static const String version\s*=\s*'([^']+)'", Path('lib/core/app_meta.dart').read_text())
if not version or not meta or version[1] != meta[1] or int(version[2]) < 1:
    sys.exit('pubspec.yaml and AppMeta must have matching versions and a positive build number')
print(version[1], version[2])
PY
)
output="${output:-$repo/dist/v$version+$build_number}"
output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
if [ -e "$output" ] || [ -L "$output" ]; then
  printf 'Output already exists; choose a new directory: %s\n' "$output" >&2
  exit 1
fi
if [ -n "$certificate" ] && ! [[ "$certificate" =~ ^([[:xdigit:]]{2}:?){31}[[:xdigit:]]{2}$ ]]; then
  printf '%s\n' 'Certificate SHA-256 must contain 64 hexadecimal digits.' >&2
  exit 2
fi
parent="$(dirname "$output")"
mkdir -p "$parent"
stage="$(mktemp -d "$parent/.blisten-apks.XXXXXX")"
trap 'exit_code=$?; rm -rf "$stage"; exit "$exit_code"' EXIT

flutter --version --machine > "$stage/flutter-version.json"
java -version > "$stage/java-version.txt" 2>&1
set --
if [ -n "$certificate" ]; then set -- --certificate-sha256 "$certificate"; fi

for variant in arm64-v8a armeabi-v7a x86_64 universal; do
  case "$variant" in
    arm64-v8a) target='android-arm64'; abis='arm64-v8a' ;;
    armeabi-v7a) target='android-arm'; abis='armeabi-v7a' ;;
    x86_64) target='android-x64'; abis='x86_64' ;;
    universal) target='android-arm,android-arm64,android-x64'; abis='armeabi-v7a,arm64-v8a,x86_64' ;;
  esac
  printf 'Building %s, version %s+%s\n' "$variant" "$version" "$build_number"
  ORG_GRADLE_PROJECT_blistenTargetAbis="$abis" flutter build apk --release \
    --target-platform "$target" --build-name "$version" --build-number "$build_number"
  name="Blisten-v$version-$variant.apk"
  cp "$repo/build/app/outputs/flutter-apk/app-release.apk" "$stage/$name"
  python3 "$repo/tool/apk-metadata.py" "$stage/$name" --release \
    --expect-abis "$abis" --expect-package com.bting.audio --expect-version "$version" \
    --expect-code "$build_number" --expect-min-sdk 24 "$@" \
    > "$stage/$variant.json"
done

python3 - "$stage" "$output" <<'PY'
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

stage, output = map(Path, sys.argv[1:])
variants = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal']
artifacts = [json.loads((stage / (variant + '.json')).read_text()) for variant in variants]
if any(item['certificate_sha256'] != artifacts[0]['certificate_sha256'] for item in artifacts[1:]):
    sys.exit('APK certificate mismatch: all four APKs must use the same signing certificate')
commit = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True)
status = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
manifest = {
    'schema_version': 1,
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'git_commit': commit.stdout.strip() if commit.returncode == 0 else None,
    'git_dirty': bool(status.stdout.strip()) if status.returncode == 0 else None,
    'flutter': json.loads((stage / 'flutter-version.json').read_text()),
    'java': (stage / 'java-version.txt').read_text().strip(),
    'artifacts': artifacts,
}
(stage / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
(stage / 'SHA256SUMS').write_text(''.join(f'{item["sha256"]}  {item["file"]}\n' for item in artifacts))
# mkdir fails if another process created the destination. Hard links publish only
# fully verified files, never replace an existing file, and avoid copying APKs.
output.mkdir()
published = []
try:
    for name in [item['file'] for item in artifacts] + ['manifest.json', 'SHA256SUMS']:
        destination = output / name
        os.link(stage / name, destination)
        published.append(destination)
except BaseException:
    for path in published:
        path.unlink()
    output.rmdir()
    raise
print(f'Validated APKs and checksums: {output}')
PY
