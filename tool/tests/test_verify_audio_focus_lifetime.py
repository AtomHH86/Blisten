"""Mock-only guards for the real background audio lifetime runner."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(os.environ.get('BLISTEN_LIFETIME_RUNNER',
    str(Path(__file__).resolve().parents[1] / 'verify-audio-focus-lifetime.py')))
spec = importlib.util.spec_from_file_location('lifetime_probe', SOURCE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

ACTIVITIES = 'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\n'
PACKAGE = ('Package [com.bting.audio.debug] (123):\n'
           '  pkgFlags=[ DEBUGGABLE HAS_CODE ]\n')
SERVICE = ('ACTIVITY MANAGER SERVICES (dumpsys activity services)\n'
           '  * ServiceRecord{123 u0 com.bting.audio.debug/'
           'com.ryanheise.audioservice.AudioService}\n'
           '    isForeground=true foregroundId=1124 types=0x00000002\n')

class ProbeGuards(unittest.TestCase):
    def test_wrong_avd_cannot_launch_flutter(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(probe, 'adb', return_value='some_other_avd\nOK\n'), \
                patch.object(probe.subprocess, 'Popen') as launch:
            with self.assertRaises(ValueError):
                probe.run('emulator-5554', Path(directory))
            launch.assert_not_called()

    def test_foreground_flag_must_belong_to_audio_service(self):
        mixed = SERVICE.replace('isForeground=true', 'isForeground=false') + (
            '  * ServiceRecord{456 u0 com.bting.audio.debug/.OtherService}\n'
            '    isForeground=true foregroundId=99 types=0x00000002\n')
        def adb(_serial, *args):
            if args[:4] == ('shell', 'dumpsys', 'activity', 'activities'):
                return ACTIVITIES
            if args[:4] == ('shell', 'dumpsys', 'activity', 'services'):
                return mixed
            if args[:3] == ('shell', 'dumpsys', 'package'):
                return PACKAGE
            return 'Broadcast completed: result=0\n'
        with tempfile.TemporaryDirectory() as directory, patch.object(probe, 'adb', side_effect=adb) as calls:
            with self.assertRaises(ValueError):
                probe.send_noisy('emulator-5554', Path(directory))
            self.assertFalse(any('broadcast' in call.args for call in calls.call_args_list))

    def test_one_real_media_service_block_allows_broadcast(self):
        def adb(_serial, *args):
            if args[:4] == ('shell', 'dumpsys', 'activity', 'activities'):
                return ACTIVITIES
            if args[:4] == ('shell', 'dumpsys', 'activity', 'services'):
                return SERVICE
            if args[:3] == ('shell', 'dumpsys', 'package'):
                return PACKAGE
            return 'Broadcast completed: result=0\n'
        with tempfile.TemporaryDirectory() as directory, patch.object(probe, 'adb', side_effect=adb) as calls:
            probe.send_noisy('emulator-5554', Path(directory))
            self.assertTrue(any('broadcast' in call.args for call in calls.call_args_list))

    def test_failed_dumpsys_is_not_activity_destruction_evidence(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(probe, 'adb', return_value='Error: service unavailable'):
            with self.assertRaises(ValueError):
                probe.send_noisy('emulator-5554', Path(directory))

    def test_driver_exit_zero_without_actual_noisy_callback_is_not_pass(self):
        process = Mock(pid=4321, returncode=0)
        process.poll.side_effect = [None, 0, 0]
        def launch(*args, **kwargs):
            kwargs['stdout'].write('BLISTEN_READY_FOR_NATIVE_NOISY\nAll tests passed!\n')
            kwargs['stdout'].flush()
            return process
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(probe, 'verify_device'), \
                patch.object(probe.subprocess, 'Popen', side_effect=launch), \
                patch.object(probe, 'send_noisy'), \
                patch.object(probe.time, 'sleep'), \
                patch.object(probe, 'adb', return_value=''):
            with self.assertRaises(RuntimeError):
                probe.run('emulator-5554', Path(directory))

    def test_cleanup_kills_only_owned_group_and_force_stops_even_if_reap_fails(self):
        process = Mock(pid=4321, returncode=None)
        process.poll.return_value = None
        process.wait.side_effect = subprocess.TimeoutExpired('flutter', 10)
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(probe, 'verify_device'), \
                patch.object(probe.subprocess, 'Popen', return_value=process) as launch, \
                patch.object(probe.time, 'monotonic', side_effect=[0, 1000]), \
                patch.object(probe, 'adb', return_value='') as adb, \
                patch('os.killpg') as kill_group:
            with self.assertRaises((TimeoutError, subprocess.SubprocessError)):
                probe.run('emulator-5554', Path(directory))
            self.assertTrue(launch.call_args.kwargs.get('start_new_session'))
            self.assertTrue(kill_group.called)
            self.assertTrue(all(call.args[0] == 4321 for call in kill_group.call_args_list))
            adb.assert_any_call('emulator-5554', 'shell', 'am', 'force-stop', probe.PACKAGE)

if __name__ == '__main__':
    unittest.main()
