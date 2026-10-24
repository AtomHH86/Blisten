"""Real shell/subprocess guards with PATH-only fake tools; no SDK or device access.

BLISTEN_ANDROID_RUNNER optionally selects an archived runner for negative checks.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(os.environ.get('BLISTEN_ANDROID_RUNNER',
    str(Path(__file__).resolve().parents[1] / 'test-android.sh')))


class ShellRunnerGuards(unittest.TestCase):
    def run_runner(self, *, serial='emulator-5554', avd='abts_api35_x86_64',
                   fail_force_stop=False, fail_restore=False):
        with tempfile.TemporaryDirectory(prefix='blisten-runner-shell-') as temporary:
            root = Path(temporary)
            tool = root / 'tool'
            fake = root / 'fake-bin'
            tool.mkdir()
            fake.mkdir()
            shutil.copyfile(SOURCE, tool / 'test-android.sh')
            (tool / 'android-env.sh').write_text('export PATH="$FAKE_BIN:$PATH"\n')
            emulator = tool / 'android-emulator.sh'
            emulator.write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_SERIAL"\n')
            emulator.chmod(0o755)

            def executable(name, body):
                file = fake / name
                file.write_text('#!/bin/sh\n' + body)
                file.chmod(0o755)

            executable('flutter', '''printf 'flutter %s\\n' "$*" >> "$CALL_LOG"
case "$*" in *integration_test/visual_design_test.dart*) touch "$STATE_DIR/final-visual" ;; esac
exit 0
''')
            executable('python3', '''printf 'python3 %s\\n' "$*" >> "$CALL_LOG"
exit 0
''')
            executable('adb', '''printf 'adb %s\\n' "$*" >> "$CALL_LOG"
[ "$1" = '-s' ] || exit 90
shift 2
case "$*" in
  'get-state') printf 'device\\n' ;;
  'emu avd name') printf '%s\\nOK\\n' "$FAKE_AVD" ;;
  'shell getprop ro.kernel.qemu') printf '1\\n' ;;
  'shell pm path com.bting.audio.debug') printf 'package:/fake/debug/base.apk\\n' ;;
  'shell am force-stop com.bting.audio.debug')
    if [ -f "$STATE_DIR/final-visual" ]; then
      if [ -f "$STATE_DIR/post-visual-stop" ] && [ "$FAIL_FORCE_STOP" = 1 ]; then exit 17; fi
      touch "$STATE_DIR/post-visual-stop"
    fi
    ;;
  'shell pm clear-permission-flags com.bting.audio.debug android.permission.POST_NOTIFICATIONS user-set user-fixed')
    touch "$STATE_DIR/restoring"
    ;;
  'shell pm grant com.bting.audio.debug android.permission.POST_NOTIFICATIONS')
    if [ -f "$STATE_DIR/restoring" ] && [ "$FAIL_RESTORE" = 1 ]; then exit 18; fi
    ;;
esac
exit 0
''')
            env = dict(os.environ, FAKE_BIN=str(fake), FAKE_SERIAL=serial,
                       FAKE_AVD=avd, CALL_LOG=str(root / 'calls.txt'),
                       STATE_DIR=str(root), FAIL_FORCE_STOP=str(int(fail_force_stop)),
                       FAIL_RESTORE=str(int(fail_restore)))
            env['PATH'] = str(fake) + os.pathsep + env['PATH']
            result = subprocess.run(['bash', str(tool / 'test-android.sh'), 'integration'],
                cwd=root, env=env, capture_output=True, text=True, timeout=15)
            call_log = root / 'calls.txt'
            self.assertTrue(call_log.is_file(),
                f'Fake tools were never reached; shell exit={result.returncode}\n'
                f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}')
            calls = call_log.read_text().splitlines()
            records = list((root / 'build/desktop-tests').glob('*/exit-code.txt'))
            recorded = records[0].read_text().strip() if records else None
            return result, calls, recorded

    def assert_no_device_mutation(self, calls):
        mutations = [call for call in calls if call.startswith('adb ') and any(
            action in call for action in ('force-stop', ' pm grant ', ' pm revoke ',
                'set-permission-flags', 'clear-permission-flags', ' install '))]
        self.assertEqual(mutations, [])

    def test_rejected_phone_never_reaches_exit_cleanup_mutation(self):
        result, calls, recorded = self.run_runner(serial='physical-phone-123')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_device_mutation(calls)
        self.assertEqual(recorded, str(result.returncode))

    def test_other_avd_never_runs_tests_or_mutates_debug_app(self):
        result, calls, recorded = self.run_runner(avd='personal_avd')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_device_mutation(calls)
        self.assertFalse(any('flutter drive' in call for call in calls))
        self.assertEqual(recorded, str(result.returncode))

    def test_final_force_stop_failure_changes_success_to_failure(self):
        result, calls, recorded = self.run_runner(fail_force_stop=True)
        self.assertTrue(any('integration_test/visual_design_test.dart' in call for call in calls))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Requested checks passed.', result.stdout)
        self.assertEqual(recorded, str(result.returncode))

    def test_permission_restore_failure_changes_success_to_failure(self):
        result, calls, recorded = self.run_runner(fail_restore=True)
        self.assertTrue(any('clear-permission-flags' in call for call in calls))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Requested checks passed.', result.stdout)
        self.assertEqual(recorded, str(result.returncode))

    def test_valid_dedicated_device_and_cleanup_can_pass(self):
        result, calls, recorded = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Requested checks passed.', result.stdout)
        self.assertEqual(recorded, '0')
        mutations = [call for call in calls if call.startswith('adb ') and 'force-stop' in call]
        self.assertTrue(mutations)
        self.assertTrue(all('adb -s emulator-5554 ' in call and
            'com.bting.audio.debug' in call for call in mutations))


if __name__ == '__main__':
    unittest.main()
