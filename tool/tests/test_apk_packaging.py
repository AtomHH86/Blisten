import hashlib
import importlib.util
import struct
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'pubspec.lock').is_file())
CHECKER = Path(os.environ.get('BLISTEN_APK_METADATA', ROOT / 'tool/apk-metadata.py'))
SPEC = importlib.util.spec_from_file_location('apk_metadata', CHECKER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
PAGE = 16384
NAME = 'lib/arm64-v8a/libfixture.so'
ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64']
CERT = 'a' * 64

FIXTURE_CODE = 'import struct\nimport zipfile\nPAGE = 16384\ndef elf(bits=64, align=PAGE, offset=0, address=0, endian=\'<\'):\n    """Small ET_DYN file with one valid, in-bounds PT_LOAD program header."""\n    ident = b\'\\x7fELF\' + bytes([2 if bits == 64 else 1, 1 if endian == \'<\' else 2, 1]) + bytes(9)\n    if bits == 64:\n        header = struct.pack(endian + \'HHIQQQIHHHHHH\', 3, 183, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0)\n        program = struct.pack(endian + \'IIQQQQQQ\', 1, 5, offset, address, address, 128, 128, align)\n    else:\n        header = struct.pack(endian + \'HHIIIIIHHHHHH\', 3, 40, 1, 0, 52, 0, 0, 52, 32, 1, 0, 0, 0)\n        program = struct.pack(endian + \'IIIIIIII\', 1, offset, address, address, 128, 128, 5, align)\n    return (ident + header + program).ljust(max(128, offset + 128), b\'\\0\')\n\n\ndef add_native(archive, name, payload, *, aligned=True):\n    info = zipfile.ZipInfo(name)\n    info.compress_type = zipfile.ZIP_STORED\n    if aligned:\n        count = -(archive.fp.tell() + 30 + len(name.encode())) % 16384\n        if 0 < count < 4:\n            count += 16384\n        info.extra = b\'\' if count == 0 else struct.pack(\'<HH\', 0xcafe, count - 4) + bytes(count - 4)\n    archive.writestr(info, payload)\n'
exec(FIXTURE_CODE)


def write_apk(path, abis, *, debug=False, code=1, min_sdk=24, extra_abi=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        for abi in abis:
            for lib in ['libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so']:
                add_native(archive, f'lib/{abi}/{lib}', elf(bits=32 if abi == 'armeabi-v7a' else 64))
        if extra_abi:
            add_native(archive, f'lib/{extra_abi}/libmpv.so', elf())
        archive.writestr('manifest-tree.txt', 'E: manifest\n  E: application\n    A: android:extractNativeLibs(0x010104ea)=(type 0x12)0x0')
        archive.writestr('badging.txt', (
            f"package: name='com.bting.audio' versionCode='{code}' versionName='1.0.0'\n"
            f"sdkVersion:'{min_sdk}'\ntargetSdkVersion:'36'\n"
        ))
        archive.writestr('signature.txt', (
            'Verifies\nVerified using v2 scheme (APK Signature Scheme v2): true\n'
            f"Signer #1 certificate DN: CN={'Android Debug' if debug else 'Release Fixture'}, O=Test\n"
            f'Signer #1 certificate SHA-256 digest: {CERT}\n'
        ))


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tools = self.root / 'sdk/build-tools/35.0.0'
        self.tools.mkdir(parents=True)
        for name, member in [('aapt', 'badging.txt'), ('apksigner', 'signature.txt')]:
            self.executable(self.tools / name,
                '#!/usr/bin/env python3\nimport sys, zipfile\n'
                f'with zipfile.ZipFile(next(a for a in sys.argv[1:] if a.endswith(".apk"))) as archive: print(archive.read("manifest-tree.txt" if "xmltree" in sys.argv else {member!r}).decode())\n')

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def inspect(self, apk, *extra):
        return subprocess.run([
            sys.executable, str(CHECKER), str(apk),
            '--build-tools', str(self.tools), '--release',
            '--expect-abis', 'arm64-v8a', '--expect-package', 'com.bting.audio',
            '--expect-version', '1.0.0', '--expect-code', '1', '--expect-min-sdk', '24',
            *extra,
        ], text=True, capture_output=True)

    def test_valid_release_reports_real_archive_size_hash_and_identity(self):
        apk = self.root / 'valid.apk'
        write_apk(apk, ['arm64-v8a'])
        result = self.inspect(apk, '--certificate-sha256', CERT)
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads(result.stdout)
        self.assertEqual(metadata.get('version_code'), 1)
        self.assertEqual(metadata['abis'], ['arm64-v8a'])
        self.assertEqual(metadata['size_bytes'], apk.stat().st_size)
        self.assertEqual(metadata['sha256'], hashlib.sha256(apk.read_bytes()).hexdigest())
        self.assertEqual(metadata['certificate_sha256'], [CERT])

    def test_rejects_extra_plugin_abi_without_flutter_engine(self):
        apk = self.root / 'extra.apk'
        write_apk(apk, ['arm64-v8a'], extra_abi='x86_64')
        result = self.inspect(apk)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ABI', result.stderr)

    def test_rejects_debug_certificate_in_release_mode(self):
        apk = self.root / 'debug-signed.apk'
        write_apk(apk, ['arm64-v8a'], debug=True)
        result = self.inspect(apk)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('debug', result.stderr.lower())

    def test_signature_verification_failure_stops_inspection(self):
        apk = self.root / 'invalid-signature.apk'
        write_apk(apk, ['arm64-v8a'])
        self.executable(self.tools / 'apksigner', '#!/bin/sh\nprintf "DOES NOT VERIFY\\n" >&2\nexit 1\n')
        result = self.inspect(apk)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DOES NOT VERIFY', result.stderr)

    def test_rejects_release_without_native_audio_library(self):
        apk = self.root / 'missing-library.apk'
        write_apk(apk, ['arm64-v8a'])
        with zipfile.ZipFile(apk) as archive:
            members = {name: archive.read(name) for name in archive.namelist()
                       if not name.endswith('/libmpv.so')}
        with zipfile.ZipFile(apk, 'w') as archive:
            for name, content in members.items():
                archive.writestr(name, content)
        result = self.inspect(apk)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('libmpv.so', result.stderr)

    def test_rejects_version_code_min_sdk_and_certificate_mismatch(self):
        for kwargs, option, error in [
            ({'code': 2003}, [], 'versionCode'),
            ({'min_sdk': 23}, [], 'minSdk'),
            ({}, ['--certificate-sha256', 'b' * 64], 'certificate'),
        ]:
            with self.subTest(error=error):
                apk = self.root / 'mismatch.apk'
                write_apk(apk, ['arm64-v8a'], **kwargs)
                result = self.inspect(apk, *option)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stderr)

    def prepare_project(self, *, signing=True):
        project = self.root / 'project'
        (project / 'tool').mkdir(parents=True)
        (project / 'android/app').mkdir(parents=True)
        (project / 'lib/core').mkdir(parents=True)
        for name in ['build-android-apks.sh', 'apk-metadata.py', 'android-env.sh']:
            shutil.copy2(CHECKER if name == 'apk-metadata.py' else ROOT / 'tool' / name, project / 'tool' / name)
        (project / 'pubspec.yaml').write_text('version: 1.0.0+1\n')
        (project / 'lib/core/app_meta.dart').write_text("static const String version = '1.0.0';\n")
        if signing:
            (project / 'android/key.properties').write_text(
                'storeFile=fixture.keystore\nstorePassword=fixture\nkeyAlias=release\nkeyPassword=fixture\n')
            (project / 'android/app/fixture.keystore').write_bytes(b'fixture only')
        flutter = self.root / 'flutter/bin/flutter'
        self.executable(flutter, '#!/usr/bin/env python3\n' + FIXTURE_CODE + '''
import json, os, pathlib, sys, zipfile
if '--version' in sys.argv:
    print(json.dumps({'frameworkVersion': 'test fixture', 'dartSdkVersion': 'test fixture'}))
    sys.exit(0)
with open(os.environ['BUILD_LOG'], 'a') as log: log.write(json.dumps({'args': sys.argv[1:], 'abis': os.environ.get('ORG_GRADLE_PROJECT_blistenTargetAbis')}) + '\\n')
abis = os.environ['ORG_GRADLE_PROJECT_blistenTargetAbis'].split(',')
target = sys.argv[sys.argv.index('--target-platform') + 1]
expected = {'android-arm64': 'arm64-v8a', 'android-arm': 'armeabi-v7a', 'android-x64': 'x86_64'}
if set(abis) != {expected[p] for p in target.split(',')}: sys.exit(9)
path = pathlib.Path('build/app/outputs/flutter-apk/app-release.apk')
path.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(path, 'w') as z:
    for abi in abis:
        for lib in ['libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so']:
            add_native(z, f'lib/{abi}/{lib}', elf(bits=32 if abi == 'armeabi-v7a' else 64))
    if os.getenv('BAD_PLUGIN') and 'x86_64' in abis:
        add_native(z, 'lib/x86_64/libbadplugin.so', elf(align=4096))
    z.writestr('manifest-tree.txt', 'E: manifest\\n  E: application\\n    A: android:extractNativeLibs(0x010104ea)=(type 0x12)0x0')
    code = 2003 if os.getenv('BAD_APK') and 'x86_64' in abis else 1
    z.writestr('badging.txt', f"package: name='com.bting.audio' versionCode='{code}' versionName='1.0.0'\\nsdkVersion:'24'\\ntargetSdkVersion:'36'\\n")
    z.writestr('signature.txt', 'Verifies\\nSigner #1 certificate DN: CN=Release Fixture\\nSigner #1 certificate SHA-256 digest: ' + 'a'*64 + '\\n')
''')
        self.executable(self.root / 'java/bin/java', '#!/bin/sh\nprintf "fixture JDK 17\\n" >&2\n')
        env = os.environ.copy()
        env.update({
            'ABTS_TOOLCHAIN_ROOT': str(self.root),
            'FLUTTER_ROOT': str(self.root / 'flutter'),
            'ABTS_JAVA_HOME': str(self.root / 'java'),
            'BUILD_LOG': str(self.root / 'build.log'),
        })
        return project, env

    def build(self, project, env, output):
        return subprocess.run(['bash', str(project / 'tool/build-android-apks.sh'),
                               '--output', str(output)], env=env, text=True, capture_output=True)

    def test_missing_release_key_stops_before_flutter_build(self):
        project, env = self.prepare_project(signing=False)
        output = self.root / 'release'
        result = self.build(project, env, output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('key.properties', result.stderr)
        self.assertFalse(Path(env['BUILD_LOG']).exists())
        self.assertFalse(output.exists())

    def test_missing_keystore_stops_before_flutter_build(self):
        project, env = self.prepare_project()
        (project / 'android/app/fixture.keystore').unlink()
        result = self.build(project, env, self.root / 'release')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('keystore', result.stderr)
        self.assertFalse(Path(env['BUILD_LOG']).exists())

    def test_four_equal_version_packages_are_published_only_after_validation(self):
        project, env = self.prepare_project()
        output = self.root / 'release'
        result = self.build(project, env, output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(output.glob('*.apk'))), 4)
        self.assertEqual(
            sorted(p.name for p in output.glob('*.apk')),
            sorted(f'Blisten-v1.0.0-{variant}.apk' for variant in [*ABIS, 'universal']),
        )
        manifest = json.loads((output / 'manifest.json').read_text())
        self.assertEqual([item['version_code'] for item in manifest['artifacts']], [1] * 4)
        self.assertEqual(len((output / 'SHA256SUMS').read_text().splitlines()), 4)
        calls = [json.loads(line) for line in Path(env['BUILD_LOG']).read_text().splitlines()]
        self.assertEqual(len(calls), 4)
        self.assertTrue(all('--split-per-abi' not in call['args'] for call in calls))
        again = self.build(project, env, output)
        self.assertNotEqual(again.returncode, 0)
        self.assertEqual(len(Path(env['BUILD_LOG']).read_text().splitlines()), 4)

    def test_invalid_third_apk_leaves_no_published_directory(self):
        project, env = self.prepare_project()
        env['BAD_APK'] = '1'
        output = self.root / 'release'
        result = self.build(project, env, output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('versionCode', result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse(list(self.root.glob('.blisten-apks.*')))


    def test_incompatible_plugin_blocks_release_and_names_exact_member(self):
        apk = self.root / 'bad-plugin.apk'
        write_apk(apk, ['arm64-v8a'])
        with zipfile.ZipFile(apk, 'a') as archive:
            add_native(archive, 'lib/arm64-v8a/libbadplugin.so', elf(align=4096))
        result = self.inspect(apk)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('16 KiB', result.stderr)
        self.assertIn('libbadplugin.so', result.stderr)

    def test_invalid_third_plugin_apk_leaves_no_published_directory(self):
        project, env = self.prepare_project()
        env['BAD_PLUGIN'] = '1'
        output = self.root / 'release'
        result = self.build(project, env, output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('libbadplugin.so', result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse(list(self.root.glob('.blisten-apks.*')))

    def test_legacy_32bit_alignment_report_does_not_become_new_release_requirement(self):
        apk = self.root / 'legacy32.apk'
        write_apk(apk, ['armeabi-v7a'])
        with zipfile.ZipFile(apk, 'a') as archive:
            add_native(archive, 'lib/armeabi-v7a/libplugin.so', elf(bits=32, align=4096))
        result = subprocess.run([sys.executable, str(CHECKER), str(apk),
            '--build-tools', str(self.tools), '--release', '--expect-abis', 'armeabi-v7a'],
            text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)['page_size_16k']
        self.assertTrue(report['compatible'])
        row = next(r for r in report['libraries'] if r['path'].endswith('/libplugin.so'))
        self.assertFalse(row['required'])
        self.assertFalse(row['elf_aligned'])


class AlignmentRed(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        for name, body in {
            'aapt': """import sys,zipfile
with zipfile.ZipFile(next(a for a in sys.argv[1:] if a.endswith('.apk'))) as z:
 print(z.read('manifest-tree.txt' if 'xmltree' in sys.argv else 'badging.txt').decode())
""",
            'apksigner': "print('Signer #1 certificate DN: CN=Release Fixture\\nSigner #1 certificate SHA-256 digest: ' + 'a'*64)\n",
        }.items():
            tool = self.tools / name
            tool.write_text('#!/usr/bin/env python3\n' + body)
            tool.chmod(0o755)

    def inspect(self, payload, *, aligned=True, compression=zipfile.ZIP_STORED,
                extract=False, name=NAME):
        apk = self.root / 'fixture.apk'
        info = zipfile.ZipInfo(name)
        info.compress_type = compression
        # Local extra differs from central-directory offsets. Use a real extra
        # record and align the DATA, not the local-header start.
        if aligned:
            extra_length = (-(30 + len(name.encode()))) % PAGE
            if 0 < extra_length < 4:
                extra_length += PAGE
            info.extra = struct.pack('<HH', 0xcafe, extra_length - 4) + bytes(extra_length - 4)
        with zipfile.ZipFile(apk, 'w') as archive:
            archive.writestr(info, payload)
            archive.writestr('badging.txt', "package: name='com.bting.audio' versionCode='1' versionName='1.0.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\n")
            tree = 'E: manifest\n  E: application'
            if extract is not None:
                value = ('0xffffffff' if extract else '0x0') if isinstance(extract, bool) else str(extract)
                tree += '\n    A: android:extractNativeLibs(0x010104ea)=(type 0x12)' + value
            archive.writestr('manifest-tree.txt', tree)
        return MODULE.inspect_apk(apk, self.tools)['page_size_16k']

    def test_elf64_and_stored_data_alignment_pass(self):
        self.assertTrue(self.inspect(elf())['compatible'])

    def test_elf32_program_header_layout_is_supported(self):
        result = self.inspect(elf(bits=32), name='lib/armeabi-v7a/libfixture.so')
        self.assertEqual(result['libraries'][0]['elf_class'], 32)
        self.assertTrue(result['libraries'][0]['elf_aligned'])

    def test_big_endian_layout_is_parsed_from_ident(self):
        self.assertTrue(self.inspect(elf(endian='>'))['libraries'][0]['elf_aligned'])

    def test_under_aligned_load_segment_fails(self):
        self.assertFalse(self.inspect(elf(align=4096))['compatible'])

    def test_offset_address_must_be_congruent(self):
        self.assertFalse(self.inspect(elf(offset=4096, address=0))['compatible'])

    def test_zip_local_data_offset_must_be_aligned_when_stored(self):
        self.assertFalse(self.inspect(elf(), aligned=False)['compatible'])

    def test_compressed_library_with_explicit_extraction_needs_no_zip_alignment(self):
        result = self.inspect(elf(), aligned=False, compression=zipfile.ZIP_DEFLATED, extract=True)
        self.assertTrue(result['compatible'])
        self.assertIsNone(result['libraries'][0]['zip_aligned'])

    def test_compressed_library_cannot_claim_direct_loading(self):
        self.assertFalse(self.inspect(elf(), compression=zipfile.ZIP_DEFLATED, extract=False)['compatible'])

    def test_compression_does_not_fix_elf_alignment(self):
        self.assertFalse(self.inspect(elf(align=4096), compression=zipfile.ZIP_DEFLATED, extract=True)['compatible'])

    def test_truncated_program_header_is_rejected(self):
        with self.assertRaises(ValueError):
            self.inspect(elf()[:80])

    def test_non_elf_native_entry_is_rejected(self):
        with self.assertRaises(ValueError):
            self.inspect(b'fixture is not an ELF')


    def test_omitted_manifest_policy_uses_android_extraction_default(self):
        report = self.inspect(elf(), compression=zipfile.ZIP_DEFLATED, extract=None)
        self.assertTrue(report['extract_native_libs'])
        self.assertTrue(report['compatible'])

    def test_unknown_explicit_extraction_boolean_is_not_certified(self):
        with self.assertRaises(ValueError):
            self.inspect(elf(), extract='0x1234')


def programs(records, *, bits=64, phentsize=None, phoff=None):
    ident = b'\x7fELF' + bytes([2 if bits == 64 else 1, 1, 1]) + bytes(9)
    header_size, program_size = (64, 56) if bits == 64 else (52, 32)
    phoff = header_size if phoff is None else phoff
    phentsize = program_size if phentsize is None else phentsize
    total = header_size + program_size * len(records)
    if bits == 64:
        header = struct.pack('<HHIQQQIHHHHHH', 3, 183, 1, 0, phoff, 0, 0,
                             header_size, phentsize, len(records), 0, 0, 0)
    else:
        header = struct.pack('<HHIIIIIHHHHHH', 3, 40, 1, 0, phoff, 0, 0,
                             header_size, phentsize, len(records), 0, 0, 0)
    body = b''
    for record in records:
        kind = record.get('type', 1)
        offset = record.get('offset', 0)
        address = record.get('address', 0)
        size = record.get('filesz', total)
        memory = record.get('memsz', size)
        alignment = record.get('align', PAGE)
        if bits == 64:
            body += struct.pack('<IIQQQQQQ', kind, 5, offset, address, address, size, memory, alignment)
        else:
            body += struct.pack('<IIIIIIII', kind, offset, address, address, size, memory, 5, alignment)
    return ident + header + body


def padding(data_offset_without_extra):
    size = -data_offset_without_extra % PAGE
    if 0 < size < 4:
        size += PAGE
    return b'' if size == 0 else struct.pack('<HH', 0xcafe, size - 4) + bytes(size - 4)


class BoundaryRed(unittest.TestCase):
    setUp = AlignmentRed.setUp

    def inspect(self, payload, *, local_aligned=True, central_extra=None,
                prefix=False, corrupt=None):
        apk = self.root / 'boundary.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            if prefix:
                archive.writestr('prefix', b'earlier member shifts local header')
            header_offset = archive.fp.tell()
            info = zipfile.ZipInfo(NAME)
            local_extra = padding(header_offset + 30 + len(NAME.encode())) if local_aligned else b''
            info.extra = local_extra
            archive.writestr(info, payload)
            # ZipFile writes central metadata on close from this same ZipInfo.
            # Mutating now changes central extra only; local bytes are retained.
            if central_extra == 'absent':
                info.extra = b''
            elif central_extra == 'misleading_aligned':
                info.extra = padding(header_offset + 30 + len(NAME.encode()))
            archive.writestr('badging.txt', "package: name='com.bting.audio' versionCode='1' versionName='1.0.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\n")
            archive.writestr('manifest-tree.txt', 'E: manifest\n  E: application\n    A: android:extractNativeLibs(0x010104ea)=(type 0x12)0x0')
        raw = bytearray(apk.read_bytes())
        local_data_offset = header_offset + 30 + len(NAME.encode()) + len(local_extra)
        if corrupt == 'signature':
            raw[header_offset:header_offset + 4] = b'BAD!'
        elif corrupt == 'extra_length':
            struct.pack_into('<H', raw, header_offset + 28, 65535)
        elif corrupt == 'name_length':
            struct.pack_into('<H', raw, header_offset + 26, 65535)
        if corrupt:
            apk.write_bytes(raw)
        # Prove fixture geometry before calling the real metadata inspector.
        self.assertEqual(local_data_offset % PAGE == 0, local_aligned)
        if not corrupt:
            with zipfile.ZipFile(apk) as archive:
                self.assertEqual(archive.read(NAME), payload)
                if central_extra == 'absent':
                    self.assertEqual(archive.getinfo(NAME).extra, b'')
        return MODULE.inspect_apk(apk, self.tools)['page_size_16k']

    def test_aligned_local_extra_cannot_be_replaced_by_empty_central_extra(self):
        self.assertTrue(self.inspect(elf(), central_extra='absent')['compatible'])

    def test_unaligned_local_extra_cannot_be_hidden_by_padded_central_extra(self):
        self.assertFalse(self.inspect(elf(), local_aligned=False,
                                     central_extra='misleading_aligned')['compatible'])

    def test_nonzero_header_offset_is_included_in_local_data_alignment(self):
        self.assertTrue(self.inspect(elf(), prefix=True, central_extra='absent')['compatible'])

    def test_nonzero_header_offset_without_padding_fails(self):
        self.assertFalse(self.inspect(elf(), prefix=True, local_aligned=False)['compatible'])

    def test_later_under_aligned_load_is_not_skipped(self):
        self.assertFalse(self.inspect(programs([{}, {'align': 4096}]))['compatible'])

    def test_later_incongruent_load_is_not_skipped(self):
        self.assertFalse(self.inspect(programs([{}, {'address': 4096}]))['compatible'])

    def test_non_load_record_does_not_supply_load_alignment(self):
        result = self.inspect(programs([{'type': 4, 'align': 4}, {}]))
        self.assertTrue(result['compatible'])

    def test_elf32_multiple_load_record_stride_is_used(self):
        result = self.inspect(programs([{}, {'align': 4096}], bits=32))
        # Overall release policy can exempt32bit; parser must still report it.
        self.assertFalse(result['libraries'][0]['elf_aligned'])

    def test_elf64_large_alignment_is_not_truncated_to_uint32(self):
        self.assertTrue(self.inspect(programs([{'align': 1 << 32}]))['compatible'])

    def test_elf64_high_offset_cannot_wrap_into_valid_small_file(self):
        with self.assertRaises(ValueError):
            self.inspect(programs([{'offset': 1 << 32, 'address': 1 << 32}]))

    def test_program_table_out_of_bounds_is_rejected(self):
        with self.assertRaises(ValueError):
            self.inspect(programs([{}], phoff=1 << 32))

    def test_too_short_program_record_size_is_rejected(self):
        with self.assertRaises(ValueError):
            self.inspect(programs([{}], phentsize=8))

    def test_native_elf_without_load_segment_is_rejected(self):
        with self.assertRaises(ValueError):
            self.inspect(programs([{'type': 4}]))

    def test_load_file_size_cannot_exceed_memory_size(self):
        with self.assertRaises(ValueError):
            self.inspect(programs([{'filesz': 120, 'memsz': 100}]))

    def test_load_alignment_must_be_power_of_two(self):
        self.assertFalse(self.inspect(programs([{'align': PAGE + 1}]))['compatible'])

    def test_corrupt_local_header_is_not_certified_from_central_metadata(self):
        for failure in ('signature', 'extra_length', 'name_length'):
            with self.subTest(failure=failure):
                with self.assertRaises((ValueError, zipfile.BadZipFile)):
                    self.inspect(elf(), corrupt=failure)


RELRO = 0x6474e552

def relro_elf(records, bits=64):
    header_size, stride = (64, 56) if bits == 64 else (52, 32)
    ident = b'\x7fELF' + bytes([2 if bits == 64 else 1, 1, 1]) + bytes(9)
    if bits == 64:
        header = struct.pack('<HHIQQQIHHHHHH', 3, 183, 1, 0, header_size,
                             0, 0, header_size, stride, len(records), 0, 0, 0)
    else:
        header = struct.pack('<HHIIIIIHHHHHH', 3, 40, 1, 0, header_size,
                             0, 0, header_size, stride, len(records), 0, 0, 0)
    table, size = b'', header_size + stride * len(records)
    for r in records:
        kind, flags, offset, address, file_size, memory_size, align = r
        size = max(size, offset + file_size)
        if bits == 64:
            table += struct.pack('<IIQQQQQQ', kind, flags, offset, address,
                                 address, file_size, memory_size, align)
        else:
            table += struct.pack('<IIIIIIII', kind, offset, address, address,
                                 file_size, memory_size, flags, align)
    return (ident + header + table).ljust(size, b'\0')


def dedicated(next_address=None, *, shared=False):
    records = [
        (1, 5, 0, 0, 0x680, 0x680, PAGE),
        (1, 6, 0x680, 0x4680, 0x1d8, 0x1980 if shared else 0x980, PAGE),
        (RELRO, 4, 0x680, 0x4680, 0x1d8, 0x980, 1),
    ]
    if next_address is not None:
        # Offset congruence is real, including the deliberately bad tail page.
        offset = next_address % PAGE + PAGE
        records.append((1, 6, offset, next_address, 0x100, 0x100, PAGE))
    return records


class RelroRed(unittest.TestCase):
    setUp = BoundaryRed.setUp
    inspect = BoundaryRed.inspect

    def test_absent_relro_does_not_invent_a_failure(self):
        self.assertTrue(self.inspect(relro_elf([(1, 5, 0, 0, 0x680, 0x680, PAGE)]))['compatible'])

    def test_shared_load_with_aligned_relro_end_passes(self):
        records = [
            (1, 6, 0, 0, 0x5000, 0x5000, PAGE),
            (RELRO, 4, 0x3000, 0x3000, 0x1000, 0x1000, 1),
        ]
        self.assertTrue(self.inspect(relro_elf(records))['compatible'])

    def test_relro_filesz_can_exceed_memsz_when_its_protected_end_is_aligned(self):
        # Official documentation's aligned example has RELRO FileSiz>MemSiz.
        # The PT_LOAD rule filesz<=memsz must not be applied to GNU_RELRO.
        records = [
            (1, 6, 0, 0, 0x5000, 0x5000, PAGE),
            (RELRO, 4, 0x3000, 0x3000, 0x2000, 0x1000, 1),
        ]
        self.assertTrue(self.inspect(relro_elf(records))['compatible'])

    def test_shared_writable_load_with_unaligned_relro_end_fails(self):
        self.assertFalse(self.inspect(relro_elf(dedicated(shared=True)))['compatible'])

    def test_entire_dedicated_load_is_relro_without_next_load_passes(self):
        self.assertTrue(self.inspect(relro_elf(dedicated()))['compatible'])

    def test_entire_dedicated_load_with_next_writable_page_passes(self):
        self.assertTrue(self.inspect(relro_elf(dedicated(0x8000)))['compatible'])

    def test_dedicated_relro_tail_cannot_overlap_next_writable_load_same_page(self):
        self.assertFalse(self.inspect(relro_elf(dedicated(0x7800)))['compatible'])

    def test_elf32_relro_field_layout_is_parsed(self):
        result = self.inspect(relro_elf(dedicated(shared=True), bits=32))
        self.assertEqual(result['libraries'][0]['elf_class'], 32)
        self.assertFalse(result['libraries'][0]['relro_aligned'])


class ActualAlignmentRed(unittest.TestCase):
    def test_64k_load_cannot_be_only_16k_congruent(self):
        for bits in (32, 64):
            with self.subTest(bits=bits):
                data = programs([{'offset': 0, 'address': 16384, 'align': 65536}], bits=bits)
                result = MODULE.inspect_elf(data)
                self.assertFalse(result['elf_aligned'])
                self.assertTrue(any('65536' in issue for issue in result['issues']))

    def test_64k_load_with_actual_alignment_is_accepted(self):
        for bits in (32, 64):
            with self.subTest(bits=bits):
                data = programs([{'offset': 0, 'address': 65536, 'align': 65536}], bits=bits)
                self.assertTrue(MODULE.inspect_elf(data)['elf_aligned'])



def padded(start, size, next_address=None):
    offset = start % PAGE
    records = [(1, 6, offset, start, size, size, PAGE),
               (RELRO, 4, offset, start, size, 0x6000-start, 1)]
    if next_address is not None:
        records.append((1, 6, next_address % PAGE, next_address, 1, 1, PAGE))
    return records


class RealApkExceptionsRed(unittest.TestCase):
    def test_arm64_whole_load_padded_relro_next_page_passes(self):
        self.assertTrue(MODULE.inspect_elf(relro_elf(padded(0x51c0, 0x268, 0x9428)))['relro_aligned'])

    def test_x64_whole_load_padded_relro_without_later_load_passes(self):
        self.assertTrue(MODULE.inspect_elf(relro_elf(padded(0x4f20, 0x228)))['relro_aligned'])

    def test_padded_relro_cannot_protect_later_writable_same_16k_page(self):
        # RELRO ends 0x6000; protection rounds to 0x8000 on 16 KiB.
        self.assertFalse(MODULE.inspect_elf(relro_elf(padded(0x51c0, 0x268, 0x7400)))['relro_aligned'])

    def test_padding_cannot_cover_other_writable_before_declared_relro_end(self):
        self.assertFalse(MODULE.inspect_elf(relro_elf(padded(0x51c0, 0x268, 0x5800)))['relro_aligned'])

    def test_relro_padding_cannot_extend_beyond_owner_16k_mapping(self):
        records = padded(0x51c0, 0x268)
        records[1] = (RELRO, 4, 0x11c0, 0x51c0, 0x268, 0x9000-0x51c0, 1)
        with self.assertRaises(ValueError):
            MODULE.inspect_elf(relro_elf(records))

    def test_padded_relro_must_start_at_owner_start(self):
        records = padded(0x51c0, 0x268)
        records[1] = (RELRO, 4, 0x11d0, 0x51d0, 0x258, 0x6000-0x51d0, 1)
        with self.assertRaises(ValueError):
            MODULE.inspect_elf(relro_elf(records))

    def inspect_stored(self, extract, alignment=PAGE):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory)/'fixture.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libfixture.so', elf(align=alignment))
            return MODULE.inspect_alignment(apk, extract)

    def test_unaligned_stored_zip_extracted_to_filesystem_passes(self):
        report = self.inspect_stored(True)
        self.assertFalse(report['libraries'][0]['zip_aligned'])
        self.assertTrue(report['compatible'])

    def test_unaligned_stored_zip_direct_loading_still_fails(self):
        self.assertFalse(self.inspect_stored(False)['compatible'])

    def test_extraction_does_not_exempt_bad_elf(self):
        self.assertFalse(self.inspect_stored(True, alignment=4096)['compatible'])



if __name__ == '__main__':
    unittest.main()
