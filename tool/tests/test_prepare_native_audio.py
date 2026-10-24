import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tool/prepare-native-audio.py'
ABIS = {'x86_64': (2, 62), 'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40)}


class NativePreparationTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), 'Native preparation command has not been implemented')
        spec = importlib.util.spec_from_file_location('prepare_native_audio', SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.module.ROOT = self.root
        self.recipe = self.root / 'tool/native-audio'
        self.build_inputs = {
            'build.py': b'fixture build recipe',
            'sources.lock.json': b'fixture source lock',
            'ffmpeg-options.txt': b'fixture ffmpeg options',
            'patches/mpv/001.fixture.patch': b'fixture patch',
        }
        for name, payload in self.build_inputs.items():
            path = self.recipe / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
        self.source = self.root / 'build/native-audio/jniLibs'
        self.plugin = self.root / 'packages/media_kit_libs_android_audio'
        self.licenses = self.root / 'licenses'
        self.licenses.mkdir()
        (self.licenses / 'NOTICE.txt').write_text('Fixture native component notice\n')

    def fixture(self, abi):
        directory = self.source / abi
        directory.mkdir(parents=True)
        elf_class, machine = ABIS[abi]
        payload = b'\x7fELF' + bytes([elf_class, 1, 1]) + bytes(9) + struct.pack('<HH', 3, machine)
        artifacts = {}
        for name in ('libmpv.so', 'libmediakitandroidhelper.so'):
            (directory / name).write_bytes(payload + name.encode())
            artifacts[name] = hashlib.sha256((directory / name).read_bytes()).hexdigest()
        manifest = {'abi': abi, 'ndk': '28.2.13676358', 'api': 24, 'artifacts': artifacts,
                    'sources_lock_sha256': hashlib.sha256(self.build_inputs['sources.lock.json']).hexdigest(),
                    'build_inputs': {name: hashlib.sha256(payload).hexdigest() for name, payload in self.build_inputs.items()}}
        (directory / 'manifest.json').write_text(json.dumps(manifest))
        return directory

    def prepare(self, *abis):
        self.module.prepare(self.source, self.plugin, self.licenses, abis)

    def test_single_abi_preparation_needs_no_other_abis_and_copies_notices(self):
        source = self.fixture('x86_64')
        self.prepare('x86_64')
        target = self.plugin / 'android/src/main'
        self.assertEqual((target / 'jniLibs/x86_64/libmpv.so').read_bytes(), (source / 'libmpv.so').read_bytes())
        self.assertFalse((target / 'jniLibs/arm64-v8a').exists())
        self.assertEqual((target / 'assets/native-audio/licenses/NOTICE.txt').read_text(), 'Fixture native component notice\n')
        self.assertEqual((target / 'assets/native-audio/manifests/x86_64.json').read_bytes(), (source / 'manifest.json').read_bytes())

    def test_digest_mismatch_preserves_previous_prepared_library(self):
        source = self.fixture('x86_64')
        self.prepare('x86_64')
        installed = self.plugin / 'android/src/main/jniLibs/x86_64/libmpv.so'
        previous = installed.read_bytes()
        (source / 'libmpv.so').write_bytes(b'changed library')
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.prepare('x86_64')
        self.assertEqual(installed.read_bytes(), previous)

    def test_missing_required_helper_is_rejected(self):
        source = self.fixture('x86_64')
        (source / 'libmediakitandroidhelper.so').unlink()
        with self.assertRaisesRegex(ValueError, 'libmediakitandroidhelper.so'):
            self.prepare('x86_64')
        self.assertFalse((self.plugin / 'android/src/main/jniLibs').exists())

    def test_manifest_cannot_select_files_outside_abi_directory(self):
        source = self.fixture('x86_64')
        manifest = json.loads((source / 'manifest.json').read_text())
        manifest['artifacts']['../outside.so'] = '0' * 64
        (source / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'artifact'):
            self.prepare('x86_64')

    def test_matching_hash_does_not_allow_wrong_elf_architecture(self):
        source = self.fixture('x86_64')
        manifest = json.loads((source / 'manifest.json').read_text())
        library = source / 'libmpv.so'
        payload = bytearray(library.read_bytes())
        payload[18:20] = struct.pack('<H', 183)
        library.write_bytes(payload)
        manifest['artifacts']['libmpv.so'] = hashlib.sha256(payload).hexdigest()
        (source / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'ELF'):
            self.prepare('x86_64')

    def test_all_requested_inputs_are_validated_before_copying_any_abi(self):
        self.fixture('x86_64')
        with self.assertRaisesRegex(ValueError, 'arm64-v8a'):
            self.prepare('x86_64', 'arm64-v8a')
        self.assertFalse((self.plugin / 'android/src/main/jniLibs').exists())

    def test_missing_notices_prevents_preparation(self):
        self.fixture('x86_64')
        (self.licenses / 'NOTICE.txt').unlink()
        with self.assertRaisesRegex(ValueError, 'license'):
            self.prepare('x86_64')

    def test_symlinked_library_is_not_packaged(self):
        source = self.fixture('x86_64')
        library = source / 'libmpv.so'
        outside = self.root / 'outside.so'
        library.rename(outside)
        library.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.prepare('x86_64')


    def test_old_source_lock_digest_is_rejected_even_when_library_hashes_match(self):
        source = self.fixture('x86_64')
        manifest = json.loads((source / 'manifest.json').read_text())
        manifest['sources_lock_sha256'] = '0' * 64
        (source / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'sources.lock'):
            self.prepare('x86_64')
        self.assertFalse((self.plugin / 'android/src/main/jniLibs').exists())

    def test_changed_build_recipe_options_or_patch_reject_old_library_manifest(self):
        self.fixture('x86_64')
        for name, original in self.build_inputs.items():
            with self.subTest(input=name):
                path = self.recipe / name
                path.write_bytes(original + b' changed')
                with self.assertRaisesRegex(ValueError, 'SHA-256'):
                    self.prepare('x86_64')
                self.assertFalse((self.plugin / 'android/src/main/jniLibs').exists())
                path.write_bytes(original)

    def test_build_input_manifest_must_include_exact_current_patch_set(self):
        source = self.fixture('x86_64')
        manifest = json.loads((source / 'manifest.json').read_text())
        original = dict(manifest['build_inputs'])
        for change in ('missing', 'obsolete'):
            with self.subTest(change=change):
                manifest['build_inputs'] = dict(original)
                if change == 'missing':
                    del manifest['build_inputs']['patches/mpv/001.fixture.patch']
                else:
                    manifest['build_inputs']['patches/mpv/000.removed.patch'] = '0' * 64
                (source / 'manifest.json').write_text(json.dumps(manifest))
                with self.assertRaisesRegex(ValueError, 'build_inputs'):
                    self.prepare('x86_64')

    def test_unlisted_shared_library_is_rejected(self):
        source = self.fixture('x86_64')
        (source / 'libold.so').write_bytes((source / 'libmpv.so').read_bytes())
        with self.assertRaisesRegex(ValueError, 'libold.so'):
            self.prepare('x86_64')
        self.assertFalse((self.plugin / 'android/src/main/jniLibs').exists())


if __name__ == '__main__':
    unittest.main()
