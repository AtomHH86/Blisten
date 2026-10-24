#!/usr/bin/env python3
"""Build Blisten's pinned Android audio libraries without Gradle or global installs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
RECIPE = Path(__file__).resolve().parent
WORK = ROOT / 'build/native-audio'
SOURCES = WORK / 'sources'
NDK_VERSION = '28.2.13676358'
ABIS = {'x86_64': ('x86_64-linux-android', 'x86_64', 'generic'),
        'arm64-v8a': ('aarch64-linux-android', 'aarch64', 'armv8-a'),
        'armeabi-v7a': ('armv7a-linux-androideabi', 'arm', 'armv7-a')}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [RECIPE / name for name in ('build.py', 'sources.lock.json', 'ffmpeg-options.txt')]
    paths.extend(sorted((RECIPE / 'patches').rglob('*.patch')))
    return {path.relative_to(RECIPE).as_posix(): digest(path) for path in paths}


def run(args, cwd, env=None):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    SOURCES.mkdir(exist_ok=True)
    downloads = WORK / 'downloads'
    downloads.mkdir(exist_ok=True)
    for entry in json.loads((RECIPE / 'sources.lock.json').read_text()):
        archive = downloads / entry['archive']
        if not archive.exists():
            with urllib.request.urlopen(entry['url'], timeout=120) as response:
                archive.write_bytes(response.read())
        if digest(archive) != entry['sha256']:
            raise RuntimeError('Source digest mismatch: ' + entry['name'])
        destination = SOURCES / entry.get('destination', entry['name'])
        if destination.exists() and any(destination.iterdir()):
            continue
        if entry['name'] == 'waf':
            destination.mkdir(parents=True, exist_ok=True)
            shutil.copy2(archive, destination / 'waf')
            continue
        with tarfile.open(archive) as package:
            members = package.getmembers()
            top = members[0].name.split('/')[0]
            # All inputs are authenticated by the pinned SHA, and paths must remain local.
            for member in members:
                target = (SOURCES / member.name).resolve()
                if not target.is_relative_to(SOURCES.resolve()):
                    raise RuntimeError('Unsafe source archive path')
            package.extractall(SOURCES, filter='data')
        extracted = SOURCES / top
        if destination.exists():
            destination.rmdir()
        destination.parent.mkdir(parents=True, exist_ok=True)
        extracted.rename(destination)
    for patch_directory in sorted((RECIPE / 'patches').iterdir()):
        patches = sorted(patch_directory.glob('*.patch'))
        patch_hash = hashlib.sha256(b''.join(p.read_bytes() for p in patches)).hexdigest()
        source = SOURCES / patch_directory.name
        marker = source / '.blisten-patches'
        if not marker.exists():
            for patch in patches:
                run(['patch', '-p1', '--dry-run', '-i', patch], source)
                run(['patch', '-p1', '-i', patch], source)
            marker.write_text(patch_hash + '\n')
        elif marker.read_text().strip() != patch_hash:
            raise RuntimeError('Patch set changed; use a fresh source workspace')


def build(abi):
    input_digests = build_inputs()
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT', ROOT.parent / '.android-toolchain/sdk'))
    ndk = Path(os.environ.get('NDK_ROOT', sdk / 'ndk' / NDK_VERSION))
    if 'Pkg.Revision = ' + NDK_VERSION not in (ndk / 'source.properties').read_text():
        raise RuntimeError('NDK_ROOT must point to the pinned NDK ' + NDK_VERSION)
    host = 'darwin-x86_64' if os.uname().sysname == 'Darwin' else 'linux-x86_64'
    binaries = ndk / 'toolchains/llvm/prebuilt' / host / 'bin'
    cmake = Path(os.environ.get('CMAKE', sdk / 'cmake/3.22.1/bin/cmake'))
    if not cmake.exists():
        raise RuntimeError('Install SDK CMake 3.22.1 before building')
    triple, arch, cpu = ABIS[abi]
    prefix = WORK / 'prefix' / abi
    prefix.mkdir(parents=True, exist_ok=True)
    output = WORK / 'jniLibs' / abi
    output.mkdir(parents=True, exist_ok=True)
    obj = WORK / 'objects' / abi
    obj.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for name in ('CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'CPATH', 'LIBRARY_PATH', 'PKG_CONFIG_PATH', 'PKG_CONFIG_SYSROOT_DIR'):
        env.pop(name, None)
    env.update(GIT_CEILING_DIRECTORIES=str(SOURCES),
               PATH=str(binaries) + ':/usr/local/bin:' + env['PATH'],
               CC=str(binaries / (triple + '24-clang')),
               CXX=str(binaries / (triple + '24-clang++')),
               AR=str(binaries / 'llvm-ar'), RANLIB=str(binaries / 'llvm-ranlib'),
               PKG_CONFIG_LIBDIR=str(prefix / 'lib/pkgconfig'),
               CFLAGS='-fPIC', CXXFLAGS='-fPIC',
               LDFLAGS='-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--no-undefined')
    common = ['-G', 'Ninja', '-DCMAKE_MAKE_PROGRAM=' + shutil.which('ninja'),
              '-DCMAKE_TOOLCHAIN_FILE=' + str(ndk / 'build/cmake/android.toolchain.cmake'),
              '-DANDROID_ABI=' + abi, '-DANDROID_PLATFORM=android-24',
              '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG',
              '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON']
    mbed = obj / 'mbedtls'
    run([cmake, '-S', SOURCES / 'mbedtls', '-B', mbed, *common,
         '-DENABLE_TESTING=OFF', '-DENABLE_PROGRAMS=OFF', '-DUSE_SHARED_MBEDTLS_LIBRARY=OFF',
         '-DUSE_STATIC_MBEDTLS_LIBRARY=ON', '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], ROOT, env)
    run([cmake, '--build', mbed, '--parallel', '2'], ROOT, env)
    run([cmake, '--install', mbed], ROOT, env)
    ff = obj / 'ffmpeg'
    ff.mkdir(exist_ok=True)
    extra_c = '-I' + str(prefix / 'include') + ' -fPIC'
    if abi == 'armeabi-v7a':
        extra_c += ' -mfpu=neon -mcpu=cortex-a8'
    flags = [line.strip() for line in (RECIPE / 'ffmpeg-options.txt').read_text().splitlines() if line.strip()]
    run([SOURCES / 'ffmpeg/configure', '--target-os=android', '--enable-cross-compile',
         '--prefix=' + str(prefix), '--cc=' + env['CC'], '--cxx=' + env['CXX'],
         '--ar=' + env['AR'], '--ranlib=' + env['RANLIB'], '--nm=' + str(binaries / 'llvm-nm'),
         '--strip=' + str(binaries / 'llvm-strip'), '--arch=' + arch, '--cpu=' + cpu,
         '--pkg-config=pkg-config', '--extra-cflags=' + extra_c,
         '--extra-ldflags=-L' + str(prefix / 'lib') + ' ' + env['LDFLAGS'], *flags], ff, env)
    config = (ff / 'config.h').read_text()
    components = (ff / 'config_components.h').read_text()
    for setting in ('CONFIG_LIBXML2',):
        if '#define ' + setting + ' 0' not in config:
            raise RuntimeError(setting + ' must be disabled')
    for setting in ('CONFIG_DASH_DEMUXER', 'CONFIG_IMF_DEMUXER'):
        if '#define ' + setting + ' 0' not in components:
            raise RuntimeError(setting + ' must be disabled')
    run(['make', '-j2'], ff, env)
    run(['make', 'install'], ff, env)
    mpv_env = env.copy()
    mpv_env['PKG_CONFIG'] = 'pkg-config --static'
    # Old Waf 2.0.24 requires Python <=3.11; macOS's Python 3.9 is intentional.
    python = os.environ.get('BLISTEN_WAF_PYTHON', '/usr/bin/python3')
    waf = SOURCES / 'waf/waf'
    mpv_obj = obj / 'mpv'
    run([python, waf, 'configure', '--prefix=' + str(prefix), '--enable-lgpl',
         '--disable-cplayer', '--disable-vulkan', '--disable-libplacebo', '--disable-lua',
         '--disable-iconv', '--disable-jpeg', '--enable-libmpv-shared', '--disable-manpage-build',
         '-o', mpv_obj], SOURCES / 'mpv', mpv_env)
    # Waf does not track external static archive mtimes; relink after dependencies.
    (mpv_obj / 'libmpv.so').unlink(missing_ok=True)
    run([python, waf, 'build', '-j2'], SOURCES / 'mpv', mpv_env)
    run([python, waf, 'install'], SOURCES / 'mpv', mpv_env)
    helper = obj / 'helper'
    run([cmake, '-S', SOURCES / 'helper/app/src/main/cpp', '-B', helper, *common,
         '-DANDROID_STL=c++_static', '-DCMAKE_CXX_STANDARD=17'], ROOT, env)
    run([cmake, '--build', helper, '--parallel', '2'], ROOT, env)
    for source in (prefix / 'lib/libmpv.so', helper / 'libmediakitandroidhelper.so'):
        destination = output / source.name
        shutil.copy2(source, destination)
        run([binaries / 'llvm-strip', '--strip-all', destination], ROOT, env)
    if build_inputs() != input_digests:
        raise RuntimeError('Build recipe changed during compilation; rebuild from stable inputs')
    record = {'abi': abi, 'ndk': NDK_VERSION, 'api': 24,
              'sources_lock_sha256': digest(RECIPE / 'sources.lock.json'),
              'build_inputs': input_digests,
              'artifacts': {p.name: digest(p) for p in sorted(output.glob('*.so'))}}
    (output / 'manifest.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('abi', choices=[*ABIS, 'all', 'prepare'])
    options = parser.parse_args()
    prepare()
    if options.abi != 'prepare':
        for selected in ABIS if options.abi == 'all' else [options.abi]:
            build(selected)
