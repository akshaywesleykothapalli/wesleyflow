#!/usr/bin/env python3
"""Deterministic Telugu unit/audio gate. Never opens a microphone or loads model weights."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUITES = ['Telugu Unicode and mixed-script output', 'Telugu bounded PCM and segmentation']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scratch-path', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='wesley-telugu-tests-') as temporary:
        scratch = args.scratch_path or (Path(temporary) / 'Build' if os.environ.get('CI') == 'true' else ROOT / 'Evidence/Telugu/Package')
        log = Path(temporary) / 'tests.log' if os.environ.get('CI') == 'true' else ROOT / 'Evidence/Telugu/package-tests.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        # Model tests require a separate explicit opt-in; CI must remain deterministic.
        env.pop('WESLEY_TELUGU_TEST_MODEL', None)
        env.pop('WESLEY_TELUGU_TEST_WAV', None)
        command = ['/usr/bin/xcrun', 'swift', 'test', '--jobs', '2', '--package-path', str(ROOT / 'Packages/WesleyFlowCore'), '--scratch-path', str(scratch), '--filter', 'TeluguRomanizerTests|TeluguAudioTests']
        with log.open('w') as output:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=1200)
        text = log.read_text(errors='replace')
        passed = result.returncode == 0 and all(f'Suite "{suite}" passed' in text for suite in SUITES)
        print('Telugu deterministic Unicode/audio suites: ' + ('PASSED' if passed else 'FAILED'))
        return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
