#!/usr/bin/env python3
"""Package the exact source inputs, recipe and build evidence alongside the APKs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[2]
RECIPE = Path(__file__).resolve().parent
WORK = ROOT / 'build/native-audio'
ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=WORK / 'distribution')
    args = parser.parse_args()
    output = args.output.resolve()
    archive = output.with_suffix('.tar.gz')
    if output.exists() or archive.exists():
        raise SystemExit('Output already exists; choose a new output path')
    locks = json.loads((RECIPE / 'sources.lock.json').read_text())
    for entry in locks:
        source = WORK / 'downloads' / entry['archive']
        if digest(source) != entry['sha256']:
            raise SystemExit('Input hash mismatch: ' + entry['archive'])
    input_paths = [RECIPE / name for name in ('build.py', 'sources.lock.json', 'ffmpeg-options.txt')]
    input_paths.extend(sorted((RECIPE / 'patches').rglob('*.patch')))
    expected_inputs = {path.relative_to(RECIPE).as_posix(): digest(path) for path in input_paths}
    manifests = {}
    for abi in ABIS:
        source = WORK / 'jniLibs' / abi
        manifest = json.loads((source / 'manifest.json').read_text())
        if manifest.get('build_inputs') != expected_inputs:
            raise SystemExit('Build inputs changed; rebuild ' + abi)
        if manifest.get('sources_lock_sha256') != expected_inputs['sources.lock.json']:
            raise SystemExit('Source lock mismatch: ' + abi)
        if manifest['abi'] != abi:
            raise SystemExit('Wrong ABI manifest')
        for name, expected in manifest['artifacts'].items():
            if digest(source / name) != expected:
                raise SystemExit('Binary hash mismatch: ' + abi + '/' + name)
        manifests[abi] = manifest
    recipe_dest = output / 'tool/native-audio'
    shutil.copytree(RECIPE, recipe_dest, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    downloads = output / 'build/native-audio/downloads'
    downloads.mkdir(parents=True)
    for entry in locks:
        shutil.copy2(WORK / 'downloads' / entry['archive'], downloads / entry['archive'])
    evidence = output / 'evidence'
    evidence.mkdir()
    (evidence / 'artifacts.json').write_text(json.dumps(manifests, indent=2) + '\n')
    for abi in ABIS:
        target = evidence / abi
        target.mkdir()
        obj = WORK / 'objects' / abi
        for relative in ('ffmpeg/config.h', 'ffmpeg/config_components.h',
                         'ffmpeg/ffbuild/config.mak', 'ffmpeg/libavutil/ffversion.h', 'mbedtls/CMakeCache.txt',
                         'mbedtls/compile_commands.json', 'mbedtls/build.ninja',
                         'mpv/config.h', 'mpv/generated/version.h', 'mpv/c4che/_cache.py', 'helper/CMakeCache.txt'):
            source = obj / relative
            if source.exists():
                clean = source.read_text().replace(str(ROOT.parent), '<WORKSPACE>')
                (target / relative.replace('/', '-')).write_text(clean)
    for verification in sorted(WORK.glob('*-verification.json')):
        shutil.copy2(verification, evidence / verification.name)
    build_log = WORK / 'final-all-abis.log'
    if build_log.exists():
        commands = '\n'.join(line for line in build_log.read_text().splitlines() if line.startswith('+ '))
        (evidence / 'build-commands.txt').write_text(commands.replace(str(ROOT.parent), '<WORKSPACE>') + '\n')
    source_config = WORK / 'sources/mbedtls/include/mbedtls/mbedtls_config.h'
    shutil.copy2(source_config, evidence / 'mbedtls_config.h')
    toolchain = WORK / 'toolchain.json'
    if toolchain.exists():
        (evidence / 'toolchain.json').write_text(toolchain.read_text().replace(str(ROOT.parent), '<WORKSPACE>'))
    (output / 'README.txt').write_text('''Blisten Android audio corresponding source package\n\nThis archive includes complete, SHA256-locked upstream source archives (including the Mbed TLS framework submodule), all Blisten patches, build commands, license notices, and configuration evidence for the supplied three-ABI binaries.\n\nRun Python 3.12+ tool/native-audio/build.py all from this archive's root. Set ANDROID_SDK_ROOT, NDK_ROOT and CMAKE if necessary, and BLISTEN_WAF_PYTHON to Python 3.9-3.11. Install the exact toolchain versions documented in tool/native-audio/README.md. The bundled source archives allow the source preparation step to work offline. Android SDK/NDK and host build tools are separate prerequisites, not embedded here.\n\nSee tool/native-audio/licenses/ for license texts and attribution. FFmpeg is configured LGPLv3-or-later, GPL and nonfree parts disabled. Mbed TLS is used under Apache-2.0. mpv's LGPL-or-later build is enabled.\n\nUse the same-release full Blisten application source to relink rebuilt libmpv.so and libmediakitandroidhelper.so through the local Android plugin. Sign your own APK using your own certificate; no official signing secret is needed to build or use a modified application. Different signing keys do not cover-upgrade an installed official package.\n\nThis is a corresponding-source and configuration record, not a claim of byte-for-byte reproducible output across hosts or tool versions. Runtime and final APK acceptance evidence is supplied separately.\n''')
    sums = [f'{digest(path)}  {path.relative_to(output)}' for path in sorted(output.rglob('*')) if path.is_file()]
    (output / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')
    with tarfile.open(archive, 'w:gz') as package:
        package.add(output, arcname='Blisten-native-audio-source')
    print(json.dumps({'archive': str(archive), 'sha256': digest(archive), 'bytes': archive.stat().st_size,
                      'files': len(sums) + 1}, indent=2))


if __name__ == '__main__':
    main()
