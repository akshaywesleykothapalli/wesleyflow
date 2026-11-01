#!/usr/bin/env python3
"""Explicit setup only. The running dictation backend has no downloader."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request

REVISION = '5359861c739e955e79d9a303bcbc70fb988958b1'
SHA256 = '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b'
SIZE = 487601967
URL = f'https://huggingface.co/ggerganov/whisper.cpp/resolve/{REVISION}/ggml-small.bin'


def verify(path):
    if path.stat().st_size != SIZE:
        raise ValueError('Wrong model size; existing files are preserved')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != SHA256:
        raise ValueError('Model SHA-256 mismatch; existing files are preserved')


def main():
    parser = argparse.ArgumentParser(description='Install pinned multilingual Whisper Small (487.6 MB, MIT). Network is used only when --source is omitted.')
    parser.add_argument('--directory', type=Path, default=Path.home() / 'Library/Application Support/WesleyFlow/Models')
    parser.add_argument('--source', type=Path, help='Install an already downloaded file without network access')
    args = parser.parse_args()
    directory = args.directory.expanduser()
    destination = directory / 'ggml-small.bin'
    if destination.exists():
        verify(destination)
        print(f'Already verified: {destination}')
        return
    directory.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(directory).free < SIZE + 100 * 1024 * 1024:
        raise ValueError('Need at least 588 MB free for installation')
    with tempfile.NamedTemporaryFile(dir=directory, prefix='.small-', delete=False) as handle:
        temporary = Path(handle.name)
    try:
        if args.source:
            verify(args.source)
            shutil.copyfile(args.source, temporary)
        else:
            print(f'Downloading multilingual Small, MIT, {SIZE} bytes, revision {REVISION}')
            with urllib.request.urlopen(URL, timeout=60) as response, temporary.open('wb') as output:
                total = 0
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > SIZE:
                        raise ValueError('Download exceeds expected size')
                    output.write(block)
        verify(temporary)
        # Do not replace another install that raced this setup operation.
        try:
            os.link(temporary, destination)
        except FileExistsError:
            verify(destination)
        print(f'Installed and SHA-256 verified: {destination}')
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
