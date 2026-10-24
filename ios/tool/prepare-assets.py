#!/usr/bin/env python3
"""Resize the approved Bting artwork for iOS; no new artwork or edits."""
import json
from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'ios/Runner/Assets.xcassets'


def main():
    # Reuse the repository's existing sips-based packaging function without
    # running its Android/Windows output generation.
    resize = runpy.run_path(str(ROOT / 'tool/prepare-brand-assets.py'))['resize']
    source = ROOT / 'docs/design/bting-v1/production'
    app_icons = CATALOG / 'AppIcon.appiconset'
    entries = json.loads((app_icons / 'Contents.json').read_text())['images']
    written = set()
    for entry in entries:
        filename = entry['filename']
        if filename in written:
            continue
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
        resize(source / 'icon-source.png', app_icons / filename, size)
        written.add(filename)
    for scale, filename in [(1, 'LaunchImage.png'), (2, 'LaunchImage@2x.png'), (3, 'LaunchImage@3x.png')]:
        resize(source / 'mascot-source.png', CATALOG / 'LaunchImage.imageset' / filename, 160 * scale)
    print(f'Prepared {len(written)} iOS icons and 3 launch images from approved source assets.')


if __name__ == '__main__':
    main()
