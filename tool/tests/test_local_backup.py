import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    'local_backup', Path(__file__).resolve().parents[1] / 'verify-local-backup.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Device:
    def __init__(self, avd='abts_api35_x86_64', qemu='1', installed=True):
        self.avd = avd
        self.qemu = qemu
        self.installed = installed
        self.enabled = False
        self.transport = 'example.cloud/.Transport'
        self.original_transport = self.transport
        self.mutations = 0
        self.failed = False

    def run(self, *args, **kwargs):
        if args == ('get-state',):
            return 'device'
        if args == ('emu', 'avd', 'name'):
            return self.avd + '\nOK'
        if args == ('shell', 'getprop', 'ro.kernel.qemu'):
            return self.qemu
        if args == ('shell', 'pm', 'path', 'com.bting.audio.debug'):
            return 'package:/data/app/base.apk' if self.installed else ''
        if args == ('shell', 'run-as', 'com.bting.audio.debug', 'id', '-u'):
            return '10234'
        if args == ('shell', 'bmgr', 'enabled'):
            return 'Backup Manager currently ' + ('enabled' if self.enabled else 'disabled')
        if args == ('shell', 'bmgr', 'list', 'transports'):
            return '* ' + self.transport + '\n  com.android.localtransport/.LocalTransport'
        if args[:3] == ('shell', 'bmgr', 'enable'):
            self.mutations += 1
            self.enabled = args[3] == 'true'
            return ''
        if args[:3] == ('shell', 'bmgr', 'transport'):
            self.mutations += 1
            self.transport = args[3]
            return 'Selected transport ' + self.transport
        if args == ('shell', 'bmgr', 'wipe', MODULE.LOCAL, MODULE.PACKAGE):
            return 'Wiped'
        if args == ('shell', 'pm', 'clear', MODULE.PACKAGE):
            return 'Success'
        if args == ('shell', 'am', 'force-stop', MODULE.PACKAGE):
            if not self.failed:
                self.failed = True
                raise MODULE.VerificationError('synthetic device failure')
            return ''
        raise MODULE.VerificationError('synthetic device failure')


class FailedSelectionDevice(Device):
    def run(self, *args, **kwargs):
        if args == ('shell', 'bmgr', 'transport', MODULE.LOCAL):
            # Android can report a selection failure without a nonzero exit.
            self.mutations += 1
            return 'Error: transport not registered'
        return super().run(*args, **kwargs)


class LocalBackupChecks(unittest.TestCase):
    def test_non_qemu_is_rejected_before_mutation(self):
        device = Device(qemu='0')
        with self.assertRaises(MODULE.VerificationError):
            MODULE.verify(device)
        self.assertEqual(device.mutations, 0)

    def test_wrong_avd_is_rejected_before_mutation(self):
        device = Device(avd='personal_avd')
        with self.assertRaises(MODULE.VerificationError):
            MODULE.verify(device)
        self.assertEqual(device.mutations, 0)

    def test_missing_debug_package_is_rejected_before_mutation(self):
        device = Device(installed=False)
        with self.assertRaises(MODULE.VerificationError):
            MODULE.verify(device)
        self.assertEqual(device.mutations, 0)

    def test_failed_local_selection_never_enables_cloud_backup(self):
        class GuardedDevice(FailedSelectionDevice):
            cloud_enabled = False

            def run(self, *args, **kwargs):
                if args == ('shell', 'bmgr', 'enable', 'true'):
                    self.cloud_enabled = self.transport != MODULE.LOCAL
                return super().run(*args, **kwargs)

        device = GuardedDevice()
        with self.assertRaises(MODULE.VerificationError):
            MODULE.verify(device)
        self.assertFalse(device.cloud_enabled)
        self.assertEqual(device.transport, device.original_transport)
        self.assertFalse(device.enabled)

    def test_cleanup_failure_never_reenables_cloud_with_synthetic_data(self):
        for failure in ('clear', 'clear_exception', 'disable', 'disable_exception'):
            with self.subTest(failure=failure):
                class CleanupFailureDevice(Device):
                    seeded = False
                    cloud_reenabled = False

                    def __init__(self):
                        super().__init__()
                        self.enabled = True

                    def run(self, *args, **kwargs):
                        if args == ('shell', 'am', 'force-stop', MODULE.PACKAGE):
                            return ''
                        if args[:4] == ('shell', 'run-as', MODULE.PACKAGE, 'sh'):
                            self.seeded = True
                            raise MODULE.VerificationError('failure after synthetic seed')
                        if self.seeded:
                            if args == ('shell', 'bmgr', 'enable', 'true'):
                                self.cloud_reenabled |= self.transport != MODULE.LOCAL
                            if failure in ('clear', 'clear_exception') and args == ('shell', 'pm', 'clear', MODULE.PACKAGE):
                                if failure == 'clear_exception':
                                    raise MODULE.VerificationError('transient adb failure')
                                return 'Failed'
                            if failure in ('disable', 'disable_exception') and args == ('shell', 'bmgr', 'enable', 'false'):
                                if failure == 'disable_exception':
                                    raise MODULE.VerificationError('transient adb failure')
                                return ''  # exit 0 without disabling
                        return super().run(*args, **kwargs)

                device = CleanupFailureDevice()
                with self.assertRaises(MODULE.VerificationError):
                    MODULE.verify(device)
                self.assertTrue(device.seeded)
                self.assertFalse(device.cloud_reenabled)
                self.assertEqual(device.transport, MODULE.LOCAL)
                if failure.startswith('clear'):
                    self.assertFalse(device.enabled)

    def test_failure_restores_transport_and_enabled_state(self):
        device = Device()
        with self.assertRaises(MODULE.VerificationError):
            MODULE.verify(device)
        self.assertEqual(device.transport, device.original_transport)
        self.assertFalse(device.enabled)
        self.assertGreaterEqual(device.mutations, 4)


if __name__ == '__main__':
    unittest.main()
