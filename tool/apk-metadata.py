#!/usr/bin/env python3
"""Inspect an APK using Android build tools; optionally enforce release requirements."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import struct
import sys
import zipfile


def check_release_key(path):
    if not path.is_file():
        raise ValueError(f'Missing release signing configuration: {path.name}')
    # Only test presence here; Gradle reads the actual passwords and key material.
    # Match Java Properties separators. Reject escaped storeFile paths rather than
    # interpreting them differently from Gradle's Properties.load.
    properties = {}
    for line in path.read_text(encoding='latin-1').splitlines():
        if not line.strip() or line.lstrip().startswith(('#', '!')):
            continue
        match = re.match(r'\s*([^\s=:]+)(?:\s*[=:]\s*|\s+)(.*)', line)
        if match:
            properties[match[1]] = match[2].strip()
    for key in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword'):
        if not properties.get(key):
            raise ValueError(f'key.properties is missing a non-empty {key}')
    if '\\' in properties['storeFile']:
        raise ValueError('key.properties storeFile must use an unescaped path with / separators')
    store = Path(properties['storeFile'])
    if not store.is_absolute():
        store = path.parent / 'app' / store
    if not store.is_file():
        raise ValueError('key.properties storeFile does not point to an existing keystore')


def build_tools_directory(explicit):
    if explicit:
        candidates = [Path(explicit)]
    else:
        sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
        if not sdk:
            raise ValueError('Set ANDROID_SDK_ROOT or pass --build-tools')
        candidates = sorted(
            (p for p in (Path(sdk) / 'build-tools').glob('*')
             if re.fullmatch(r'\d+(?:\.\d+)*', p.name)),
            key=lambda p: tuple(int(n) for n in p.name.split('.')), reverse=True,
        )
    for candidate in candidates:
        if all((candidate / tool).is_file() for tool in ('aapt', 'apksigner')):
            return candidate
    raise ValueError('Android build-tools with aapt and apksigner are required')


def run_tool(command):
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'{Path(command[0]).name} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result.stdout


def required_match(pattern, text, label):
    match = re.search(pattern, text, flags=re.MULTILINE)
    if not match:
        raise ValueError(f'Cannot read {label} from Android tool output')
    return match[1]


PAGE = 16384
REQUIRED_ABIS = {'arm64-v8a', 'x86_64'}


def inspect_elf(data):
    if len(data) < 16 or data[:4] != b'\x7fELF' or data[6] != 1:
        raise ValueError('Missing/invalid ELF identification')
    if data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError('Unsupported ELF class/byte order')
    bits = 32 if data[4] == 1 else 64
    endian = '<' if data[5] == 1 else '>'
    header = struct.Struct(endian + ('HHIIIIIHHHHHH' if bits == 32 else 'HHIQQQIHHHHHH'))
    program = struct.Struct(endian + ('IIIIIIII' if bits == 32 else 'IIQQQQQQ'))
    if len(data) < 16 + header.size:
        raise ValueError('Truncated ELF header')
    values = header.unpack_from(data, 16)
    version, phoff, ehsize, stride, count = values[2], values[4], values[7], values[8], values[9]
    if version != 1 or ehsize < 16 + header.size or stride < program.size or not count:
        raise ValueError('Invalid ELF program table layout')
    if count == 65535 or phoff < ehsize or phoff + stride * count > len(data):
        raise ValueError('ELF program table outside file or unsupported extended count')
    loads, segments, relros, issues = [], [], [], []
    for index in range(count):
        fields = program.unpack_from(data, phoff + stride * index)
        kind = fields[0]
        if kind not in (1, 0x6474e552):
            continue
        if bits == 32:
            _, offset, address, _, file_size, memory_size, flags, alignment = fields
        else:
            _, flags, offset, address, _, file_size, memory_size, alignment = fields
        if (kind == 1 and file_size > memory_size) or offset + file_size > len(data):
            raise ValueError(f'ELF PT_LOAD[{index}] invalid file/memory bounds')
        segment = {'index': index, 'address': address, 'memory_size': memory_size, 'flags': flags,
                   'offset': offset, 'file_size': file_size}
        if kind == 0x6474e552:
            relros.append(segment)
            continue
        segments.append(segment)
        loads.append(alignment)
        if alignment < PAGE or alignment & (alignment - 1):
            issues.append(f'PT_LOAD[{index}] p_align={alignment} is not power-of-two >=16384')
        if alignment > 1 and (offset - address) % alignment:
            issues.append(f'PT_LOAD[{index}] file/virtual offsets not congruent modulo p_align={alignment}')
        elif (offset - address) % PAGE:
            issues.append(f'PT_LOAD[{index}] file/virtual offsets not congruent modulo 16384')
    if not loads:
        raise ValueError('Native ELF has no PT_LOAD segment')
    relro_issues = []
    for relro in relros:
        start, size = relro['address'], relro['memory_size']
        if size == 0:
            continue
        end = start + size
        file_owners = [load for load in segments
                       if load['offset'] <= relro['offset'] and
                       relro['offset'] + relro['file_size'] <= load['offset'] + load['file_size']]
        owners = [load for load in file_owners if load['address'] <= start and
                  end <= load['address'] + load['memory_size']]
        # Older LLD rounds RELRO's memory size to the common page boundary,
        # even when the dedicated LOAD ends earlier. Allow only that LOAD's
        # mapped tail, and check other writable data from its actual end.
        padded = [load for load in file_owners if load['address'] == start and
                  load['address'] + load['memory_size'] < end <=
                  (load['address'] + load['memory_size'] + PAGE - 1) // PAGE * PAGE]
        if not owners and not padded:
            raise ValueError('GNU_RELRO is not contained in a PT_LOAD segment/mapped tail')
        if end % PAGE == 0 and owners:
            continue
        dedicated = [load for load in owners if load['address'] == start and
                     load['memory_size'] == size] + padded
        protected_end = (end + PAGE - 1) // PAGE * PAGE
        actual_end = min((load['address'] + load['memory_size'] for load in dedicated), default=end)
        sharing_tail = [load for load in segments if load['flags'] & 2 and
                        load['address'] < protected_end and
                        load['address'] + load['memory_size'] > actual_end]
        if not dedicated or sharing_tail:
            relro_issues.append(f'GNU_RELRO[{relro["index"]}] unaligned end shares writable LOAD/page')
    aligned = not issues
    issues.extend(relro_issues)
    return {'elf_class': bits, 'load_alignments': loads, 'elf_aligned': aligned,
            'relro_aligned': not relro_issues, 'issues': issues}


def local_data_offset(source, info, archive_size):
    source.seek(info.header_offset)
    header = source.read(30)
    if len(header) != 30:
        raise ValueError('Truncated ZIP local header')
    signature, _, flags, compression, _, _, _, _, _, name_size, extra_size = struct.unpack('<IHHHHHIIIHH', header)
    if (signature != 0x04034b50 or flags & 1 or info.flag_bits & 1 or
            compression != info.compress_type):
        raise ValueError('Invalid/encrypted/inconsistent ZIP local header')
    offset = info.header_offset + 30 + name_size + extra_size
    if offset + info.compress_size > archive_size:
        raise ValueError('ZIP local data outside archive')
    # ZipFile.read separately validates member names, compressed contents and CRC.
    return offset


def inspect_alignment(path, extract_native_libs):
    libraries = []
    with path.open('rb') as source, zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            parts = info.filename.split('/')
            if len(parts) != 3 or parts[0] != 'lib' or not parts[2].endswith('.so'):
                continue
            data_offset = local_data_offset(source, info, path.stat().st_size)
            try:
                result = inspect_elf(archive.read(info))
            except ValueError as error:
                raise ValueError(f'{info.filename}: {error}') from error
            if info.compress_type == zipfile.ZIP_STORED:
                zip_aligned = data_offset % PAGE == 0
                if not zip_aligned and not extract_native_libs:
                    result['issues'].append(f'Stored ZIP data offset {data_offset} is not 16 KiB aligned')
            elif info.compress_type == zipfile.ZIP_DEFLATED:
                zip_aligned = None
                if not extract_native_libs:
                    result['issues'].append('Compressed native library requires extraction')
            else:
                raise ValueError('Unsupported native ZIP compression')
            result.update(path=info.filename, zip_aligned=zip_aligned,
                          zip_data_offset=data_offset, required=parts[1] in REQUIRED_ABIS,
                          compatible=not result['issues'])
            libraries.append(result)
    return {'compatible': all(row['compatible'] for row in libraries if row['required']),
            'extract_native_libs': extract_native_libs, 'libraries': libraries}


def extraction_policy(path, tools):
    tree = run_tool([str(tools / 'aapt'), 'dump', 'xmltree', str(path), 'AndroidManifest.xml'])
    if not re.search(r'E:\s+manifest\b', tree) or not re.search(r'E:\s+application\b', tree):
        raise ValueError('Cannot read application extraction policy from AndroidManifest.xml')
    declarations = re.findall(r'^\s*A:\s+android:extractNativeLibs(?:\([^)]*\))?=(.*)$', tree, re.MULTILINE)
    if not declarations:
        return True  # Android application attribute default; extraction enabled.
    if len(declarations) != 1:
        raise ValueError('Ambiguous extractNativeLibs policy')
    value = declarations[0].strip()
    if value in ('true', '(type 0x12)0xffffffff'):
        return True
    if value in ('false', '(type 0x12)0x0'):
        return False
    raise ValueError('Unsupported extractNativeLibs boolean representation')


def inspect_apk(path, tools):
    badging = run_tool([str(tools / 'aapt'), 'dump', 'badging', str(path)])
    signature = run_tool([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(path)])
    certificates = sorted(set(re.findall(
        r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$', signature, re.MULTILINE)))
    if not certificates:
        raise ValueError('Cannot read signing certificate SHA-256 from apksigner')
    native = {}
    page_alignment = inspect_alignment(path, extraction_policy(path, tools))
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            match = re.fullmatch(r'lib/([^/]+)/([^/]+\.so)', name)
            if match:
                native.setdefault(match[1], []).append(match[2])
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return {
        'file': path.name,
        'size_bytes': path.stat().st_size,
        'sha256': digest.hexdigest(),
        'application_id': required_match(r"^package:.*? name='([^']+)'", badging, 'applicationId'),
        'version_name': required_match(r"^package:.*? versionName='([^']+)'", badging, 'versionName'),
        'version_code': int(required_match(r"^package:.*? versionCode='(\d+)'", badging, 'versionCode')),
        'min_sdk': int(required_match(r"^sdkVersion:'(\d+)'", badging, 'minSdk')),
        'target_sdk': int(required_match(r"^targetSdkVersion:'(\d+)'", badging, 'targetSdk')),
        'debuggable': bool(re.search(r'^application-debuggable\s*$', badging, re.MULTILINE)),
        'abis': sorted(native),
        'flutter_abis': sorted(abi for abi, libs in native.items() if 'libflutter.so' in libs),
        'native_libraries': {abi: sorted(libs) for abi, libs in sorted(native.items())},
        'page_size_16k': page_alignment,
        'signature_verified': True,
        'certificate_sha256': [value.lower() for value in certificates],
        'certificate_dn': re.findall(r'^Signer #\d+ certificate DN: (.+)$', signature, re.MULTILINE),
    }


def validate(metadata, args):
    for field, expected, label in (
        ('application_id', args.expect_package, 'applicationId'),
        ('version_name', args.expect_version, 'versionName'),
        ('version_code', args.expect_code, 'versionCode'),
        ('min_sdk', args.expect_min_sdk, 'minSdk'),
    ):
        if expected is not None and metadata[field] != expected:
            raise ValueError(f'{label}: expected {expected}, got {metadata[field]}')
    if args.expect_abis:
        expected = sorted(set(args.expect_abis.split(',')))
        if metadata['abis'] != expected or metadata['flutter_abis'] != expected:
            raise ValueError(f'ABI mismatch: expected {expected}, native={metadata["abis"]}, Flutter={metadata["flutter_abis"]}')
    if args.release:
        if metadata['debuggable'] or any(re.search(r'\bCN\s*=\s*Android Debug\b', dn, re.I)
                                         for dn in metadata['certificate_dn']):
            raise ValueError('Release APK must not be debuggable or signed by an Android debug certificate')
        if not metadata['abis'] or not metadata['certificate_dn']:
            raise ValueError('Release APK is missing native libraries or signing certificate identity')
        required = {'libapp.so', 'libflutter.so', 'libmpv.so', 'libmediakitandroidhelper.so'}
        for abi, libs in metadata['native_libraries'].items():
            missing = required.difference(libs)
            if missing:
                raise ValueError(f'ABI {abi} is missing required libraries: {sorted(missing)}')
        alignment = metadata['page_size_16k']
        if not alignment['compatible']:
            failures = [f'{item["path"]}: {"; ".join(item["issues"])}'
                        for item in alignment['libraries']
                        if item['required'] and not item['compatible']]
            raise ValueError('16 KiB native alignment failed: ' + ' | '.join(failures))
    if args.certificate_sha256:
        expected = args.certificate_sha256.lower().replace(':', '')
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('Expected certificate SHA-256 must have 64 hexadecimal digits')
        if metadata['certificate_sha256'] != [expected]:
            raise ValueError('Signing certificate SHA-256 does not match the expected certificate')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', nargs='?', type=Path)
    parser.add_argument('--check-release-key', type=Path)
    parser.add_argument('--build-tools')
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--expect-abis')
    parser.add_argument('--expect-package')
    parser.add_argument('--expect-version')
    parser.add_argument('--expect-code', type=int)
    parser.add_argument('--expect-min-sdk', type=int)
    parser.add_argument('--certificate-sha256')
    args = parser.parse_args()
    try:
        if args.check_release_key:
            check_release_key(args.check_release_key)
            print('Release signing configuration and keystore are present.')
            return
        if not args.apk:
            parser.error('provide an APK or --check-release-key')
        metadata = inspect_apk(args.apk, build_tools_directory(args.build_tools))
        validate(metadata, args)
        print(json.dumps(metadata, ensure_ascii=False, indent=2))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'APK validation failed: {error}\n')


if __name__ == '__main__':
    main()
