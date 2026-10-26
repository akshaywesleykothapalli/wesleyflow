#!/usr/bin/env python3
"""Shared local/CI commands. Raw compiler/test output stays in ignored local files."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANUAL_TESTS = [
    'GlobalCoordinatorTests/nativePagesInstantiateInBothAppearancesWithoutStartingSpeech()',
    'GlobalCoordinatorTests/compactPagesAccommodateLargerTextWithoutExpandingTheMinimumWindow()',
    'GlobalCoordinatorTests/compactDefaultHomeAndWindowUpdatesPreserveUserGeometryWithoutVoice()',
    'SettingsRowLayoutTests/actualNativeControlFramesShareTrailingEdge()',
]


def version(text):
    match = re.search(r'(\d+)\.(\d+)', text)
    if not match:
        raise ValueError('version-unavailable')
    return tuple(map(int, match.groups()))


def preflight(env):
    developer = Path(env.get('DEVELOPER_DIR', ''))
    if not developer.is_absolute() or not developer.is_dir() or not str(developer).endswith('.app/Contents/Developer'):
        raise ValueError('Select a full Xcode with DEVELOPER_DIR')
    def output(command):
        return subprocess.check_output(command, env=env, stderr=subprocess.DEVNULL, text=True)
    xcode = output(['/usr/bin/xcodebuild', '-version'])
    swift = output(['/usr/bin/xcrun', 'swift', '--version'])
    sdk = output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'])
    if (platform.machine() != 'arm64' or version(platform.mac_ver()[0]) < (26, 0)
            or version(xcode) != (27, 0) or version(swift) < (6, 4) or version(sdk) < (27, 0)):
        raise ValueError('Requires arm64 macOS26+, Xcode27.0, Swift6.4+ and macOS27+ SDK')
    if sys.version_info < (3, 11):
        raise ValueError('Python3.11+ required')
    return {'xcode': '.'.join(map(str, version(xcode))), 'swift': '.'.join(map(str, version(swift))),
            'sdk': '.'.join(map(str, version(sdk))), 'architecture': platform.machine()}


def xcode_command(action, directory):
    common = ['/usr/bin/xcodebuild', '-project', 'WesleyFlow.xcodeproj', '-scheme', 'WesleyFlow',
              '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(directory / 'DerivedData'),
              '-disableAutomaticPackageResolution', '-skipPackageUpdates', '-jobs', '2']
    if action == 'test':
        return common + ['-configuration', 'Debug', '-parallel-testing-enabled', 'NO',
                         '-resultBundlePath', str(directory / 'tests.xcresult'), 'test'] + [
            '-skip-testing:WesleyFlowAppTests/' + test for test in MANUAL_TESTS]
    return common + ['-configuration', 'Debug' if action == 'debug' else 'Release'] + (
        ['SWIFT_STRICT_CONCURRENCY=complete'] if action == 'concurrency' else []) + ['build']


def run(command, env, log):
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
    return result.returncode



def gui_executed(node):
    if isinstance(node, dict):
        if node.get("nodeIdentifier") in MANUAL_TESTS and node.get("result") not in (None, "Skipped"):
            return True
        return any(gui_executed(value) for value in node.values())
    return isinstance(node, list) and any(gui_executed(value) for value in node)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['preflight', 'test', 'debug', 'release', 'concurrency', 'model-lab'])
    parser.add_argument('--output', type=Path, default=ROOT / 'Evidence/CI/local')
    args = parser.parse_args()
    env = os.environ.copy()
    env.pop('SDKROOT', None)
    if env.get('CI') == 'true':
        # No artifacts/cache uploads; never emit raw logs, result bundles or paths.
        directory = Path(tempfile.mkdtemp(prefix='wesley-ci-', dir=env.get('RUNNER_TEMP')))
    else:
        directory = args.output.resolve()
        directory.mkdir(parents=True, exist_ok=True)
    summary = {'action': args.action, 'result': 'FAILED'}
    try:
        summary['toolchain'] = preflight(env)
        code = 0
        if args.action == 'model-lab':
            commands = [[sys.executable, 'ModelLab/build_validator.py'],
                        [sys.executable, '-m', 'unittest', 'discover', '-s', 'ModelLab/tests', '-v'],
                        [sys.executable, '-m', 'unittest', 'discover', '-s', 'ModelLab/NativeDiagnostics', '-p', 'test_*.py', '-v']]
        elif args.action == 'preflight':
            commands = []
        else:
            commands = [xcode_command(args.action, directory)]
        for index, command in enumerate(commands):
            code = run(command, env, directory / f'{args.action}-{index}.log')
            if args.action == 'model-lab' and index > 0 and not code:
                match = re.search(r'^Ran (\d+) tests? in ', (directory / f'{args.action}-{index}.log').read_text(errors='replace'), re.MULTILINE)
                count = int(match.group(1)) if match else 0
                summary['modelLabTests' if index == 1 else 'resourceGuardTests'] = count
                if count < (143 if index == 1 else 7):
                    code = 1
            if code:
                break
        if code:
            summary['exitCode'] = code
        elif args.action == 'test':
            command = ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(directory / 'tests.xcresult')]
            result = subprocess.run(command, env=env, capture_output=True, timeout=60)
            if result.returncode:
                raise ValueError('test-summary-unavailable')
            data = json.loads(result.stdout)
            configurations = data['devicesAndConfigurations']
            cases = sum(item['passedTests'] for item in configurations)
            if cases < 999 or data['failedTests'] or data['result'] != 'Passed':
                raise ValueError('test-count-or-result')
            tree_result = subprocess.run(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(directory / 'tests.xcresult')], env=env, capture_output=True, timeout=60)
            if tree_result.returncode:
                raise ValueError('test-selection-unavailable')
            if gui_executed(json.loads(tree_result.stdout)):
                raise ValueError('manual-test-exclusion-not-honored')
            summary.update(passedCases=cases, passedDeclarations=data['passedTests'], failed=data['failedTests'], result='PASSED')
        else:
            summary['result'] = 'PASSED'
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        # Do not echo exception/source lines, personal paths or private test text.
        summary['diagnostic'] = 'Toolchain or check failed; reproduce locally with the documented command.'
    (directory / f'{args.action}-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary))
    return summary['result'] != 'PASSED'


if __name__ == '__main__':
    sys.exit(main())
