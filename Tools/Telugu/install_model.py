#!/usr/bin/env python3
"""Explicit setup only. No downloader is linked to runtime dictation."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request

MODELS = {
    'multilingual': {'file': 'ggml-small.bin', 'size': 487601967, 'sha256': '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b', 'repo': 'ggerganov/whisper.cpp', 'revision': '5359861c739e955e79d9a303bcbc70fb988958b1', 'license': 'MIT'},
    'telugu': {'file': 'ggml-telugu-small-q8_0.bin', 'size': 264464607, 'sha256': '355cef20a0d433ca6ffae35d414c817e0aeecfce21b934d68203efee1e72dcba', 'repo': 'jacobsamas/shorts-studio-models', 'revision': 'bd01ed7929666163b173b826e56d6dcdf8afb8ce', 'license': 'Apache-2.0'},
}


def verify(path, model):
    if path.stat().st_size != model['size']:
        raise ValueError('Wrong model size; existing files are preserved')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != model['sha256']:
        raise ValueError('Model SHA-256 mismatch; existing files are preserved')


def install(directory, model, source=None):
    destination = directory / model['file']
    if destination.exists():
        verify(destination, model)
        print(f'Already verified: {destination}')
        return
    if source:
        verify(source, model)
    directory.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(directory).free < model['size'] + 100 * 1024 * 1024:
        raise ValueError('Insufficient free space for model installation')
    with tempfile.NamedTemporaryFile(dir=directory, prefix='.whisper-', delete=False) as handle:
        temporary = Path(handle.name)
    try:
        if source:
            shutil.copyfile(source, temporary)
        else:
            print(f"Downloading {model['file']}, {model['license']}, {model['size']} bytes, revision {model['revision']}")
            url = f"https://huggingface.co/{model['repo']}/resolve/{model['revision']}/{model['file']}"
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
                total = 0
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > model['size']:
                        raise ValueError('Download exceeds expected size')
                    output.write(block)
        verify(temporary, model)
        try:
            os.link(temporary, destination)
        except FileExistsError:
            verify(destination, model)
        print(f'Installed and SHA-256 verified: {destination}')
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description='Install pinned offline Small models. Telugu-only needs the specialist; Auto also needs multilingual Small. No network is used with --source.')
    parser.add_argument('--directory', type=Path, default=Path.home() / 'Library/Application Support/WesleyFlow/Models')
    parser.add_argument('--model', choices=['both', 'telugu', 'multilingual'], default='both')
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    keys = list(MODELS) if args.model == 'both' else [args.model]
    if args.source:
        keys = [key for key in keys if MODELS[key]['size'] == args.source.stat().st_size]
        if len(keys) != 1:
            raise ValueError('Source does not match one selected pinned model')
    for key in keys:
        install(args.directory.expanduser(), MODELS[key], args.source)


if __name__ == '__main__':
    main()
