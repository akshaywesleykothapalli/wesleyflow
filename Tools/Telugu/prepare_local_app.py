#!/usr/bin/env python3
"""Prepare an explicit ad-hoc local install; never alter signed distribution settings."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def local_entitlements(existing):
    value = dict(existing)
    if value.get('com.apple.security.device.audio-input') is not True:
        raise ValueError('Expected Wesley Flow audio entitlement')
    value['com.apple.security.cs.disable-library-validation'] = True
    return value


def prepare(source, destination):
    if destination.exists():
        raise ValueError('Destination already exists; preserve it')
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.wesleyflow.WesleyFlow':
        raise ValueError('Unexpected app identity')
    signature = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=2', str(source)], capture_output=True, check=True, text=True)
    if 'Signature=adhoc' not in signature.stderr:
        raise ValueError('This helper is only for explicit ad-hoc local builds; use normal signing for distribution')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(source)], check=True)
    result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(source)], capture_output=True, check=True)
    entitlements = local_entitlements(plistlib.loads(result.stdout))
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Work on a new copy. The build product and production entitlements stay unchanged.
    shutil.copytree(source, destination, symlinks=True)
    with tempfile.TemporaryDirectory(prefix='wesley-local-signing-') as temporary:
        path = Path(temporary) / 'local.entitlements'
        path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements', str(path), str(destination)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(destination)], check=True)
    print('Prepared explicit local ad-hoc app with app-scoped library-validation exception:', destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.source.resolve(), args.destination.resolve())


if __name__ == '__main__':
    main()
