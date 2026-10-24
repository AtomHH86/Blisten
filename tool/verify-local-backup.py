#!/usr/bin/env python3
"""Destructive synthetic acceptance on the dedicated debug emulator app only.

Run after installing the current debug APK. Clears that app's data before/after
verification. Uses Android's local transport, never a phone or cloud backup.
"""
import base64
import re
import shlex
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

SERIAL = 'emulator-5554'
PACKAGE = 'com.bting.audio.debug'
AVD = 'abts_api35_x86_64'
LOCAL = 'com.android.localtransport/.LocalTransport'
PREFS = 'shared_prefs/FlutterSharedPreferences.xml'
AUDIO = 'files/audio_cache/synthetic_backup_audio.bin'
SESSION = 'no_backup/bili_session'


class VerificationError(RuntimeError):
    pass


class Adb:
    def __init__(self):
        self.executable = shutil.which('adb')
        if not self.executable:
            raise VerificationError('adb not found; source tool/android-env.sh first')

    def run(self, *args, timeout=180):
        # One shell command string preserves argument boundaries through adb.
        command = [self.executable, '-s', SERIAL]
        command += ['shell', shlex.join(args[1:])] if args[0] == 'shell' else list(args)
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise VerificationError('adb operation could not complete') from None
        if result.returncode:
            # Device output can include preferences. Never include it in errors.
            raise VerificationError('adb operation failed; raw output withheld')
        return result.stdout.replace('\r', '').strip()


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def app(device, script):
    return device.run('shell', 'run-as', PACKAGE, 'sh', '-c', script)


def preferences(device):
    try:
        root = ET.fromstring(app(device, 'cat ' + PREFS))
        return {node.attrib.get('name'): node.text or '' for node in root}
    except ET.ParseError:
        raise VerificationError('restored preferences are not valid XML') from None


def verify(device):
    require(device.run('get-state') == 'device', 'dedicated emulator is unavailable')
    require(device.run('shell', 'getprop', 'ro.kernel.qemu') == '1',
            'refusing non-emulator target')
    require(device.run('emu', 'avd', 'name').splitlines()[0] == AVD,
            'refusing a different AVD on emulator-5554')
    require(device.run('shell', 'pm', 'path', PACKAGE).startswith('package:'),
            'current debug package is not installed')
    require(device.run('shell', 'run-as', PACKAGE, 'id', '-u').isdigit(),
            'debug package does not allow isolated run-as access')
    state = device.run('shell', 'bmgr', 'enabled')
    require(state in ('Backup Manager currently enabled',
                      'Backup Manager currently disabled'), 'unknown bmgr enabled state')
    enabled = state.endswith(' enabled')
    transport_lines = device.run('shell', 'bmgr', 'list', 'transports').splitlines()
    active = [line.strip()[2:].strip() for line in transport_lines
              if line.strip().startswith('* ')]
    transports = [line.strip().removeprefix('* ').strip() for line in transport_lines]
    require(len(active) == 1 and LOCAL in transports, 'local/current transport unavailable')
    original = active[0]
    marker = uuid.uuid4().hex
    cookie = 'SESSDATA=SYNTHETIC_LOCAL_BACKUP_' + marker
    favorite = '[{"syntheticFavorite":"' + marker + '"}]'
    root = ET.Element('map')
    for key, value in {'flutter.bili_cookie': cookie,
                       'flutter.abts_shelf': favorite,
                       'flutter.synthetic_backup_setting': marker}.items():
        ET.SubElement(root, 'string', name=key).text = value
    encoded = base64.b64encode(ET.tostring(root, encoding='utf-8')).decode('ascii')
    cleanup_errors = []
    try:
        print('Valid target; selecting local transport before enabling backup.', flush=True)
        device.run('shell', 'bmgr', 'transport', LOCAL)
        selected = device.run('shell', 'bmgr', 'list', 'transports').splitlines()
        require([line.strip()[2:].strip() for line in selected
                 if line.strip().startswith('* ')] == [LOCAL],
                'local transport selection failed; backup remains disabled')
        device.run('shell', 'bmgr', 'enable', 'true')
        device.run('shell', 'am', 'force-stop', PACKAGE)
        require(device.run('shell', 'pm', 'clear', PACKAGE) == 'Success', 'initial app reset failed')
        app(device, 'mkdir -p shared_prefs files/audio_cache; '
            + "printf '%s' " + shlex.quote(encoded) + ' | base64 -d > ' + PREFS
            + "; printf '%s' synthetic-audio > " + AUDIO)
        # pm clear marks the package stopped, which makes Android refuse backup.
        # The existing media receiver ignores this non-media action; it merely
        # clears stopped state without launching Flutter or migrating the cookie.
        device.run('shell', 'am', 'broadcast', '--include-stopped-packages',
                   '-n', PACKAGE + '/com.ryanheise.audioservice.MediaButtonReceiver',
                   '-a', PACKAGE + '.TEST_BACKUP_PREPARE')
        package_state = device.run('shell', 'dumpsys', 'package', PACKAGE)
        require(re.search(r'User 0:[^\n]*\bstopped=false\b', package_state) is not None,
                'synthetic test package remains stopped and ineligible for backup')
        require(preferences(device).get('flutter.bili_cookie') == cookie,
                'legacy cookie migrated before backup-agent acceptance boundary')
        require(not app(device, 'if [ -e ' + SESSION +
                        ' ]; then echo unexpected-session; fi'),
                'isolated session exists before backup-agent migration')
        device.run('shell', 'bmgr', 'wipe', LOCAL, PACKAGE)
        print('Seeded synthetic legacy session/settings/favorite/audio; requesting full backup.', flush=True)
        # Official testing flow initializes metadata before the manifest's full
        # backup operation: https://developer.android.com/identity/data/testingbackup
        # Direct fullbackup can silently do nothing on an uninitialized dataset.
        result = device.run('shell', 'bmgr', 'backupnow', PACKAGE)
        require(re.search(r'Package\s+' + re.escape(PACKAGE) +
                          r'\s+with result:\s*Success\b', result) is not None and
                re.search(r'Backup finished with result:\s*Success\b', result) is not None,
                'package backup did not explicitly report success')
        before = preferences(device)
        require('flutter.bili_cookie' not in before, 'backup did not migrate legacy credentials')
        require(app(device, 'cat ' + SESSION) == cookie, 'isolated session migration failed')
        require(before.get('flutter.abts_shelf') == favorite and
                before.get('flutter.synthetic_backup_setting') == marker,
                'backup preparation damaged ordinary settings/favorite')
        sets = device.run('shell', 'bmgr', 'list', 'sets')
        tokens = re.findall(r'^\s*([0-9a-fA-F]+)\s*:', sets, re.MULTILINE)
        # LocalTransport's current restore set is 1; reject ambiguous alternatives.
        require('1' in tokens, 'current local restore set unavailable')
        require(device.run('shell', 'pm', 'clear', PACKAGE) == 'Success', 'restore app reset failed')
        result = device.run('shell', 'bmgr', 'restore', '1', PACKAGE)
        require(re.search(r'restoreFinished:\s*0\b', result) is not None,
                'local restore did not report success')
        restored = preferences(device)
        require(restored.get('flutter.abts_shelf') == favorite,
                'favorite was not restored from this backup')
        require(restored.get('flutter.synthetic_backup_setting') == marker,
                'setting was not restored from this backup')
        require('flutter.bili_cookie' not in restored, 'legacy credentials entered backup')
        absent = app(device, 'for p in ' + SESSION + ' ' + SESSION + '.bak '
                     + SESSION + '.new ' + AUDIO
                     + '; do if [ -e "$p" ]; then echo forbidden; fi; done')
        require(not absent, 'credential or audio file was restored')
        print('PASS: favorites/settings restored; legacy/isolated credentials and audio excluded.', flush=True)
    finally:
        # A failed command can also exit zero. Confirm disable and data removal
        # before permitting the original (possibly cloud) transport again.
        try:
            device.run('shell', 'bmgr', 'enable', 'false')
            require(device.run('shell', 'bmgr', 'enabled') ==
                    'Backup Manager currently disabled', 'backup disable not confirmed')
        except VerificationError:
            cleanup_errors.append('disable')
        for args in [('shell', 'bmgr', 'wipe', LOCAL, PACKAGE),
                     ('shell', 'am', 'force-stop', PACKAGE),
                     ('shell', 'pm', 'clear', PACKAGE)]:
            try:
                output = device.run(*args)
                if args[1:3] == ('pm', 'clear'):
                    require(output == 'Success', 'synthetic app clear not confirmed')
                elif args[1:3] == ('bmgr', 'wipe'):
                    require(not re.search(r'(?i)error|failed', output), 'local wipe failed')
            except VerificationError:
                cleanup_errors.append(args[2])
        if not cleanup_errors:
            try:
                device.run('shell', 'bmgr', 'transport', original)
                selected = device.run('shell', 'bmgr', 'list', 'transports').splitlines()
                require([line.strip()[2:].strip() for line in selected
                         if line.strip().startswith('* ')] == [original],
                        'original transport restoration not confirmed')
                device.run('shell', 'bmgr', 'enable', str(enabled).lower())
                require(device.run('shell', 'bmgr', 'enabled') ==
                        'Backup Manager currently ' + ('enabled' if enabled else 'disabled'),
                        'original backup enabled state not confirmed')
            except VerificationError:
                cleanup_errors.append('restore_state')
        if cleanup_errors:
            # Never re-enable cloud with unconfirmed synthetic-data cleanup.
            # Retry only the safe local/disabled state, then require inspection.
            for args in [('shell', 'bmgr', 'transport', LOCAL),
                         ('shell', 'bmgr', 'enable', 'false')]:
                try:
                    device.run(*args)
                except VerificationError:
                    pass
            raise VerificationError('cleanup incomplete; local/disabled state attempted; '
                                    'manual bmgr/app state check required')
        print('Restored original bmgr enabled/transport state; synthetic app/backup cleared.', flush=True)


if __name__ == '__main__':
    try:
        verify(Adb())
    except VerificationError as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
