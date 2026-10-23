import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64']
CERT = 'a' * 64


def write_apk(path, abis, *, debug=False, code=3, min_sdk=24, extra_abi=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        for abi in abis:
            for lib in ['libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so']:
                archive.writestr(f'lib/{abi}/{lib}', b'fixture')
        if extra_abi:
            archive.writestr(f'lib/{extra_abi}/libmpv.so', b'fixture')
        archive.writestr('badging.txt', (
            f"package: name='dev.pages.abts' versionCode='{code}' versionName='1.2.0'\n"
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
                f'with zipfile.ZipFile(sys.argv[-1]) as archive: print(archive.read({member!r}).decode())\n')

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def inspect(self, apk, *extra):
        return subprocess.run([
            sys.executable, str(ROOT / 'tool/apk-metadata.py'), str(apk),
            '--build-tools', str(self.tools), '--release',
            '--expect-abis', 'arm64-v8a', '--expect-package', 'dev.pages.abts',
            '--expect-version', '1.2.0', '--expect-code', '3', '--expect-min-sdk', '24',
            *extra,
        ], text=True, capture_output=True)

    def test_valid_release_reports_real_archive_size_hash_and_identity(self):
        apk = self.root / 'valid.apk'
        write_apk(apk, ['arm64-v8a'])
        result = self.inspect(apk, '--certificate-sha256', CERT)
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads(result.stdout)
        self.assertEqual(metadata.get('version_code'), 3)
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
            shutil.copy2(ROOT / 'tool' / name, project / 'tool' / name)
        (project / 'pubspec.yaml').write_text('version: 1.2.0+3\n')
        (project / 'lib/core/app_meta.dart').write_text("static const String version = '1.2.0';\n")
        if signing:
            (project / 'android/key.properties').write_text(
                'storeFile=fixture.keystore\nstorePassword=fixture\nkeyAlias=release\nkeyPassword=fixture\n')
            (project / 'android/app/fixture.keystore').write_bytes(b'fixture only')
        flutter = self.root / 'flutter/bin/flutter'
        self.executable(flutter, '''#!/usr/bin/env python3
import json, os, pathlib, sys, zipfile
if '--version' in sys.argv:
    print(json.dumps({'frameworkVersion': 'test fixture', 'dartSdkVersion': 'test fixture'}))
    sys.exit(0)
with open(os.environ['BUILD_LOG'], 'a') as log: log.write(json.dumps({'args': sys.argv[1:], 'abis': os.environ.get('ORG_GRADLE_PROJECT_abtsTargetAbis')}) + '\\n')
abis = os.environ['ORG_GRADLE_PROJECT_abtsTargetAbis'].split(',')
target = sys.argv[sys.argv.index('--target-platform') + 1]
expected = {'android-arm64': 'arm64-v8a', 'android-arm': 'armeabi-v7a', 'android-x64': 'x86_64'}
if set(abis) != {expected[p] for p in target.split(',')}: sys.exit(9)
path = pathlib.Path('build/app/outputs/flutter-apk/app-release.apk')
path.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(path, 'w') as z:
    for abi in abis:
        for lib in ['libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so']:
            z.writestr(f'lib/{abi}/{lib}', b'fixture')
    code = 2003 if os.getenv('BAD_APK') and 'x86_64' in abis else 3
    z.writestr('badging.txt', f"package: name='dev.pages.abts' versionCode='{code}' versionName='1.2.0'\\nsdkVersion:'24'\\ntargetSdkVersion:'36'\\n")
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
        manifest = json.loads((output / 'manifest.json').read_text())
        self.assertEqual([item['version_code'] for item in manifest['artifacts']], [3] * 4)
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
        self.assertFalse(list(self.root.glob('.abts-apks.*')))


if __name__ == '__main__':
    unittest.main()
