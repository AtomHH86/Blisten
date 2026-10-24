#!/usr/bin/env python3
"""Verify self-built audio libraries and stage them in the local Android plugin."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ABIS = {'x86_64': (2, 62), 'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40)}
REQUIRED = {'libmpv.so', 'libmediakitandroidhelper.so'}
ALLOWED = REQUIRED | {'libc++_shared.so'}


def checked_file(path):
    if path.is_symlink():
        raise ValueError('Refusing symlink: ' + str(path))
    if not path.is_file():
        raise ValueError('Missing file: ' + str(path))
    return path.read_bytes()


def validate_abi(source, abi, build_inputs):
    directory = source / abi
    if directory.is_symlink():
        raise ValueError('Refusing symlink: ' + str(directory))
    raw_manifest = checked_file(directory / 'manifest.json')
    manifest = json.loads(raw_manifest)
    if manifest.get('abi') != abi or manifest.get('api') != 24:
        raise ValueError('Incorrect ABI or API in manifest for ' + abi)
    if manifest.get('sources_lock_sha256') != build_inputs['sources.lock.json']:
        raise ValueError('SHA-256 mismatch for sources.lock.json in ' + abi)
    recorded_inputs = manifest.get('build_inputs')
    if not isinstance(recorded_inputs, dict) or set(recorded_inputs) != set(build_inputs):
        raise ValueError('build_inputs must contain the exact current recipe and patch set for ' + abi)
    for name, digest in build_inputs.items():
        if recorded_inputs[name] != digest:
            raise ValueError('SHA-256 mismatch for build input ' + name + ' in ' + abi)
    artifacts = manifest.get('artifacts')
    if not isinstance(artifacts, dict) or not REQUIRED.issubset(artifacts) or not set(artifacts).issubset(ALLOWED):
        raise ValueError('Unexpected or missing native artifact in ' + abi)
    actual_libraries = {path.relative_to(directory).as_posix() for path in directory.rglob('*.so')
                        if path.is_file() or path.is_symlink()}
    if actual_libraries != set(artifacts):
        raise ValueError('Native artifact set differs from manifest in ' + abi + ': ' +
                         ', '.join(sorted(actual_libraries.symmetric_difference(artifacts))))
    files = {}
    for name, expected in artifacts.items():
        payload = checked_file(directory / name)
        if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected) or hashlib.sha256(payload).hexdigest() != expected:
            raise ValueError('SHA-256 mismatch: ' + str(directory / name))
        elf_class, machine = ABIS[abi]
        if (len(payload) < 20 or payload[:4] != b'\x7fELF' or
                payload[4:7] != bytes([elf_class, 1, 1]) or
                struct.unpack('<HH', payload[16:20]) != (3, machine)):
            raise ValueError('ELF architecture/type does not match ' + abi + ': ' + name)
        files[name] = payload
    return raw_manifest, files


def prepare(source, plugin, licenses, abis):
    # Validate every input before replacing any previously prepared library.
    recipe = ROOT / 'tool/native-audio'
    inputs = [recipe / name for name in ('build.py', 'sources.lock.json', 'ffmpeg-options.txt')]
    inputs.extend(sorted((recipe / 'patches').rglob('*.patch')))
    build_inputs = {path.relative_to(recipe).as_posix(): hashlib.sha256(checked_file(path)).hexdigest()
                    for path in inputs}
    records = {abi: validate_abi(source, abi, build_inputs) for abi in abis}
    if licenses.is_symlink() or not licenses.is_dir():
        raise ValueError('Missing native license directory: ' + str(licenses))
    notices = {}
    for path in sorted(licenses.rglob('*')):
        if path.is_symlink():
            raise ValueError('Refusing license symlink: ' + str(path))
        if path.is_file():
            payload = checked_file(path)
            if not payload.strip():
                raise ValueError('Empty license file: ' + str(path))
            payload.decode('utf-8')
            notices[path.relative_to(licenses).as_posix()] = payload
    if not notices:
        raise ValueError('Native license directory is empty')

    destination = plugin / 'android/src/main'
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.native-audio-', dir=destination) as temporary:
        staging = Path(temporary)
        for abi, (manifest, files) in records.items():
            directory = staging / 'jniLibs' / abi
            directory.mkdir(parents=True)
            for name, payload in files.items():
                (directory / name).write_bytes(payload)
        for name, payload in notices.items():
            target = staging / 'licenses' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
        # Prepared files live outside build/, so flutter clean cannot remove them.
        for abi in records:
            target = destination / 'jniLibs' / abi
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                shutil.rmtree(target)
            shutil.move(staging / 'jniLibs' / abi, target)
        assets = destination / 'assets/native-audio'
        assets.mkdir(parents=True, exist_ok=True)
        if (assets / 'licenses').exists():
            shutil.rmtree(assets / 'licenses')
        shutil.move(staging / 'licenses', assets / 'licenses')
        (assets / 'licenses.json').write_text(json.dumps(
            {name: hashlib.sha256(payload).hexdigest() for name, payload in notices.items()}, indent=2) + '\n')
        (assets / 'manifests').mkdir(exist_ok=True)
        for abi, (manifest, _) in records.items():
            (assets / 'manifests' / (abi + '.json')).write_bytes(manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('abi', choices=[*ABIS, 'all'])
    options = parser.parse_args()
    selected = list(ABIS) if options.abi == 'all' else [options.abi]
    try:
        prepare(ROOT / 'build/native-audio/jniLibs', ROOT / 'packages/media_kit_libs_android_audio',
                ROOT / 'tool/native-audio/licenses', selected)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\nBuild first: python3 tool/native-audio/build.py ' + options.abi + '\n')
    print('Prepared native audio: ' + ', '.join(selected))


if __name__ == '__main__':
    main()
