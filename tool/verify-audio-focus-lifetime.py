#!/usr/bin/env python3
"""Probe background audio lifetime on the dedicated debug emulator only."""
import argparse
from pathlib import Path
import re
import signal
import sys
import subprocess
import time
import os

PACKAGE = 'com.bting.audio.debug'
AVD = 'abts_api35_x86_64'
READY = 'BLISTEN_READY_FOR_NATIVE_NOISY'
RECEIVED = 'BLISTEN_RECEIVED_NATIVE_NOISY'


def adb(serial, *arguments):
    return subprocess.check_output(['adb', '-s', serial, *arguments], text=True,
                                   stderr=subprocess.STDOUT, timeout=20)


def verify_device(serial):
    if not re.fullmatch(r'emulator-[0-9]+', serial):
        raise ValueError('Only the dedicated emulator may be used')
    names = adb(serial, 'emu', 'avd', 'name').splitlines()
    if not names or names[0].strip() != AVD:
        raise ValueError('Unexpected AVD')
    if adb(serial, 'shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
        raise ValueError('Target is not an emulator')


def repository_root():
    for parent in Path(__file__).resolve().parents:
        pubspec = parent / 'pubspec.yaml'
        if pubspec.is_file() and re.search(r'(?m)^name:\s*blisten\s*$', pubspec.read_text()):
            if not (parent / 'test_driver/integration.dart').is_file() or not (
                    parent / 'integration_test/audio_focus_lifetime_test.dart').is_file():
                raise ValueError('Missing Blisten lifetime test/driver')
            return parent
    raise ValueError('Runner must reside inside the Blisten checkout')


def send_noisy(serial, evidence):
    package = adb(serial, 'shell', 'dumpsys', 'package', PACKAGE)
    (evidence / 'package.txt').write_text(package)
    if f'Package [{PACKAGE}]' not in package or not re.search(
            r'(?:pkgFlags|flags)=\[[^\]]*\bDEBUGGABLE\b', package):
        raise ValueError('The fixed debug package must be installed and debuggable')
    activities = adb(serial, 'shell', 'dumpsys', 'activity', 'activities')
    (evidence / 'activities.txt').write_text(activities)
    if 'ACTIVITY MANAGER ACTIVITIES' not in activities:
        raise ValueError('Unrecognized Activity evidence')
    if re.search(r'ActivityRecord[^\n]*' + re.escape(PACKAGE) + r'/', activities):
        raise ValueError('App Activity must be destroyed before noisy probe')
    services = adb(serial, 'shell', 'dumpsys', 'activity', 'services', PACKAGE)
    (evidence / 'services.txt').write_text(services)
    if 'ACTIVITY MANAGER SERVICES' not in services:
        raise ValueError('Unrecognized service evidence')
    blocks = re.split(r'(?m)^(?=[ \t]*\*?[ \t]*ServiceRecord\{)', services)
    component = PACKAGE + '/com.ryanheise.audioservice.AudioService'
    found = False
    for block in blocks:
        first_line = block.splitlines()[0] if block.splitlines() else ''
        if not re.search(re.escape(component) + r'(?=[\s}])', first_line) or not re.search(r'\bisForeground=true\b', block):
            continue
        media_type = re.search(r'\btypes=(0x[0-9a-fA-F]+)', block)
        if media_type and int(media_type[1], 16) & 2:
            found = True
    if not found:
        raise ValueError('Exact foreground media-playback AudioService not observed')
    result = adb(serial, 'shell', 'su', '0', 'am', 'broadcast', '-a',
                 'android.media.AUDIO_BECOMING_NOISY', '-p', PACKAGE)
    (evidence / 'broadcast.txt').write_text(result)
    if 'Broadcast completed' not in result or re.search(r'Permission Denial|Exception|Error:', result):
        raise ValueError('Protected noisy broadcast failed')


def cleanup(process, serial):
    problem = None
    try:
        if process.poll() is None:
            for termination in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(process.pid, termination)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                    break
                except subprocess.TimeoutExpired as error:
                    problem = error
            else:
                raise problem
    finally:
        # Independent of child-reaping success; never target a replacement device.
        verify_device(serial)
        adb(serial, 'shell', 'am', 'force-stop', PACKAGE)


def run(serial, evidence):
    verify_device(serial)
    root = repository_root()
    evidence.mkdir(parents=True, exist_ok=True)
    log = evidence / 'flutter-drive.log'
    with log.open('x') as stream:
        process = subprocess.Popen([
            'flutter', 'drive', '--debug', '--driver=test_driver/integration.dart',
            '--target=integration_test/audio_focus_lifetime_test.dart',
            '-d', serial, '--no-pub', '--keep-app-running', '--timeout=600',
            '--dart-define=BLISTEN_NATIVE_NOISY_PROBE=true',
        ], cwd=root, start_new_session=True, stdout=stream, stderr=subprocess.STDOUT)
        sent = False
        end = time.monotonic() + 660
        failure = None
        try:
            while process.poll() is None:
                if not sent and READY in log.read_text(errors='replace'):
                    send_noisy(serial, evidence)
                    sent = True
                if time.monotonic() >= end:
                    raise TimeoutError('Native audio lifetime test timed out')
                time.sleep(0.5)
            text = log.read_text(errors='replace')
            after_ready = text.partition(READY)[2]
            if (process.returncode != 0 or not sent or RECEIVED not in after_ready or
                    'All tests passed' not in after_ready or
                    re.search(r'EXCEPTION CAUGHT|Test failed|Failure in method:|Unhandled exception|\[ERROR:flutter/', text)):
                raise RuntimeError(f'Native lifetime failed: exit={process.returncode}, broadcast={sent}')
        except BaseException as error:
            failure = error
            raise
        finally:
            try:
                cleanup(process, serial)
            except BaseException as error:
                if failure is None:
                    raise
                print(f'Cleanup also failed: {error}', file=sys.stderr)
    print(f'Background lifetime and native noisy callback passed; evidence: {evidence}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.serial, args.evidence_dir)
    except (ValueError, RuntimeError, TimeoutError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Native lifetime verification failed: {error}\n')


if __name__ == '__main__':
    main()
