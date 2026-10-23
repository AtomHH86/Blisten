#!/usr/bin/env python3
"""Package imagegen masters at platform sizes using macOS sips; no art edits."""
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/design/bting-v1/production'


def resize(source, target, size):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ['sips', '-z', str(size), str(size), str(source), '--out', str(target)],
        check=True, stdout=subprocess.DEVNULL,
    )


def main():
    if shutil.which('sips') is None:
        raise SystemExit('This asset packaging helper requires macOS sips.')
    mascot, icon = SOURCE / 'mascot-source.png', SOURCE / 'icon-source.png'
    resize(mascot, ROOT / 'assets/mascot.png', 512)
    resize(icon, ROOT / 'assets/logo.png', 512)
    resize(icon, ROOT / 'docs/logo.png', 512)
    # Android 12+ renders its splash icon much larger than the legacy 96dp
    # bitmap. Keep a density-independent master to avoid upscaling a small PNG.
    resize(mascot, ROOT / 'android/app/src/main/res/drawable-nodpi/splash_mascot_art.png', 1024)
    for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                           ('xxhdpi', 3), ('xxxhdpi', 4)]:
        out = ROOT / f'android/app/src/main/res/mipmap-{density}'
        resize(icon, out / 'ic_launcher.png', round(48 * scale))
        resize(mascot, out / 'ic_launcher_foreground.png', round(108 * scale))
        resize(mascot, out / 'splash_logo.png', round(96 * scale))
    # ICO directory + PNG payloads, preserving the generated art at common sizes.
    with tempfile.TemporaryDirectory(prefix='blisten-icons-') as directory:
        sizes = [16, 24, 32, 48, 64, 128, 256]
        payloads = []
        for size in sizes:
            target = Path(directory) / f'{size}.png'
            resize(icon, target, size)
            payloads.append(target.read_bytes())
        offset = 6 + 16 * len(sizes)
        entries = []
        for size, payload in zip(sizes, payloads):
            entries.append(struct.pack('<BBBBHHII', size % 256, size % 256,
                                       0, 0, 1, 32, len(payload), offset))
            offset += len(payload)
        destination = ROOT / 'windows/runner/resources/app_icon.ico'
        destination.write_bytes(struct.pack('<HHH', 0, 1, len(sizes))
                                + b''.join(entries) + b''.join(payloads))
    print('Prepared Flutter, Android and Windows icon resources from imagegen masters.')


if __name__ == '__main__':
    main()
