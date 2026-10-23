#!/usr/bin/env python3
"""Inspect an APK using Android build tools; optionally enforce release requirements."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def check_release_key(path):
    if not path.is_file():
        raise ValueError(f'Missing release signing configuration: {path.name}')
    # Only test presence here; Gradle reads the actual passwords and key material.
    # Match Java Properties separators. Reject escaped storeFile paths rather than
    # interpreting them differently from Gradle's Properties.load.
    properties = {}
    for line in path.read_text(encoding='latin-1').splitlines():
        if not line.strip() or line.lstrip().startswith(('#', '!')):
            continue
        match = re.match(r'\s*([^\s=:]+)(?:\s*[=:]\s*|\s+)(.*)', line)
        if match:
            properties[match[1]] = match[2].strip()
    for key in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword'):
        if not properties.get(key):
            raise ValueError(f'key.properties is missing a non-empty {key}')
    if '\\' in properties['storeFile']:
        raise ValueError('key.properties storeFile must use an unescaped path with / separators')
    store = Path(properties['storeFile'])
    if not store.is_absolute():
        store = path.parent / 'app' / store
    if not store.is_file():
        raise ValueError('key.properties storeFile does not point to an existing keystore')


def build_tools_directory(explicit):
    if explicit:
        candidates = [Path(explicit)]
    else:
        sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
        if not sdk:
            raise ValueError('Set ANDROID_SDK_ROOT or pass --build-tools')
        candidates = sorted(
            (p for p in (Path(sdk) / 'build-tools').glob('*')
             if re.fullmatch(r'\d+(?:\.\d+)*', p.name)),
            key=lambda p: tuple(int(n) for n in p.name.split('.')), reverse=True,
        )
    for candidate in candidates:
        if all((candidate / tool).is_file() for tool in ('aapt', 'apksigner')):
            return candidate
    raise ValueError('Android build-tools with aapt and apksigner are required')


def run_tool(command):
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'{Path(command[0]).name} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result.stdout


def required_match(pattern, text, label):
    match = re.search(pattern, text, flags=re.MULTILINE)
    if not match:
        raise ValueError(f'Cannot read {label} from Android tool output')
    return match[1]


def inspect_apk(path, tools):
    badging = run_tool([str(tools / 'aapt'), 'dump', 'badging', str(path)])
    signature = run_tool([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(path)])
    certificates = sorted(set(re.findall(
        r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$', signature, re.MULTILINE)))
    if not certificates:
        raise ValueError('Cannot read signing certificate SHA-256 from apksigner')
    native = {}
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            match = re.fullmatch(r'lib/([^/]+)/([^/]+\.so)', name)
            if match:
                native.setdefault(match[1], []).append(match[2])
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return {
        'file': path.name,
        'size_bytes': path.stat().st_size,
        'sha256': digest.hexdigest(),
        'application_id': required_match(r"^package:.*? name='([^']+)'", badging, 'applicationId'),
        'version_name': required_match(r"^package:.*? versionName='([^']+)'", badging, 'versionName'),
        'version_code': int(required_match(r"^package:.*? versionCode='(\d+)'", badging, 'versionCode')),
        'min_sdk': int(required_match(r"^sdkVersion:'(\d+)'", badging, 'minSdk')),
        'target_sdk': int(required_match(r"^targetSdkVersion:'(\d+)'", badging, 'targetSdk')),
        'debuggable': bool(re.search(r'^application-debuggable\s*$', badging, re.MULTILINE)),
        'abis': sorted(native),
        'flutter_abis': sorted(abi for abi, libs in native.items() if 'libflutter.so' in libs),
        'native_libraries': {abi: sorted(libs) for abi, libs in sorted(native.items())},
        'signature_verified': True,
        'certificate_sha256': [value.lower() for value in certificates],
        'certificate_dn': re.findall(r'^Signer #\d+ certificate DN: (.+)$', signature, re.MULTILINE),
    }


def validate(metadata, args):
    for field, expected, label in (
        ('application_id', args.expect_package, 'applicationId'),
        ('version_name', args.expect_version, 'versionName'),
        ('version_code', args.expect_code, 'versionCode'),
        ('min_sdk', args.expect_min_sdk, 'minSdk'),
    ):
        if expected is not None and metadata[field] != expected:
            raise ValueError(f'{label}: expected {expected}, got {metadata[field]}')
    if args.expect_abis:
        expected = sorted(set(args.expect_abis.split(',')))
        if metadata['abis'] != expected or metadata['flutter_abis'] != expected:
            raise ValueError(f'ABI mismatch: expected {expected}, native={metadata["abis"]}, Flutter={metadata["flutter_abis"]}')
    if args.release:
        if metadata['debuggable'] or any(re.search(r'\bCN\s*=\s*Android Debug\b', dn, re.I)
                                         for dn in metadata['certificate_dn']):
            raise ValueError('Release APK must not be debuggable or signed by an Android debug certificate')
        if not metadata['abis'] or not metadata['certificate_dn']:
            raise ValueError('Release APK is missing native libraries or signing certificate identity')
        required = {'libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so'}
        for abi, libs in metadata['native_libraries'].items():
            missing = required.difference(libs)
            if missing:
                raise ValueError(f'ABI {abi} is missing required libraries: {sorted(missing)}')
    if args.certificate_sha256:
        expected = args.certificate_sha256.lower().replace(':', '')
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('Expected certificate SHA-256 must have 64 hexadecimal digits')
        if metadata['certificate_sha256'] != [expected]:
            raise ValueError('Signing certificate SHA-256 does not match the expected certificate')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', nargs='?', type=Path)
    parser.add_argument('--check-release-key', type=Path)
    parser.add_argument('--build-tools')
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--expect-abis')
    parser.add_argument('--expect-package')
    parser.add_argument('--expect-version')
    parser.add_argument('--expect-code', type=int)
    parser.add_argument('--expect-min-sdk', type=int)
    parser.add_argument('--certificate-sha256')
    args = parser.parse_args()
    try:
        if args.check_release_key:
            check_release_key(args.check_release_key)
            print('Release signing configuration and keystore are present.')
            return
        if not args.apk:
            parser.error('provide an APK or --check-release-key')
        metadata = inspect_apk(args.apk, build_tools_directory(args.build_tools))
        validate(metadata, args)
        print(json.dumps(metadata, ensure_ascii=False, indent=2))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'APK validation failed: {error}\n')


if __name__ == '__main__':
    main()
