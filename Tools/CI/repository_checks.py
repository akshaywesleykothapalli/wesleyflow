#!/usr/bin/env python3
"""Offline, redacted repository checks. No credential values or source lines printed."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CHECKOUT = 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803'
PATTERNS = {
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'github-token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b',
    'provider-token': rb'\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{32,}\b',
    'aws-access': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'literal-bearer': rb'(?i)bearer\s+[A-Za-z0-9_\-.]{30,}',
    'credential-assignment': rb'''(?im)(?:api[_-]?key|password|client[_-]?secret|access[_-]?token)\s*[=:]\s*["'][^"'\s]{16,}["']''',
    'jwt': rb'\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\b',
}
# Exact unchanged negative-test fixture, not a filename-wide exemption.
KEY_HEADER_FIXTURE_SHA256 = '9d4f4b0e35a7035546a540af49fb252de40c5daa9eb7b73df522dd29005b410c'


def secret_kinds(data):
    found = [name for name, expression in PATTERNS.items() if re.search(expression, data)]
    if hashlib.sha256(data).hexdigest() == KEY_HEADER_FIXTURE_SHA256:
        found = [kind for kind in found if kind != 'private-key']
    return found


def artifact(path, size):
    parts = Path(path).parts
    if path.startswith(('ModelLab/artifacts/', 'ModelLab/runs/', 'ModelLab/prepared/', 'Docs/Phase1D/Hand-Drawn-Screenshots/', 'Docs/Phase1D/Reference-Screenshots/', 'Docs/Phase1D/Settings-Screenshots/', 'Docs/Phase1D/UI-Micro-Screenshots/')):
        return True
    forbidden = {'DerivedData', 'Evidence', 'Run', '.venv', '.build', '__pycache__', 'xcuserdata', 'checkpoints'}
    return (size > 5 * 1024 * 1024 or bool(forbidden.intersection(parts))
            or bool(re.search(r'(?i)\.(?:safetensors|gguf|npz|p12|pfx|mobileprovision|pem|key|sqlite3?|db|wav|m4a|heic|xcuserstate|pyc|zip)$', path))
            or Path(path).name == '.DS_Store'
            or (Path(path).name.startswith('.env') and Path(path).name != '.env.example'))


def workflow_data(path):
    # Ruby/Psych is preinstalled on both selected runner inventories. No pip install.
    command = ['ruby', '-ryaml', '-rjson', '-e',
               'puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false))', str(path)]
    result = subprocess.run(command, capture_output=True, timeout=20)
    if result.returncode:
        raise ValueError('workflow-syntax')
    return json.loads(result.stdout)


def workflow_issues(value):
    if not isinstance(value, dict):
        return ['workflow-root']
    issues = []
    if set(value.get('on', {})) != {'push', 'pull_request', 'workflow_dispatch'}:
        issues.append('workflow-events')
    if value.get('permissions') != {'contents': 'read'}:
        issues.append('workflow-permissions')
    jobs = value.get('jobs', {})
    if set(jobs) != {'repository', 'macos'}:
        issues.append('workflow-jobs')
    expected = {'repository': 'ubuntu-24.04', 'macos': 'xcode-27'}
    for name, job in jobs.items():
        if job.get('runs-on') != expected.get(name) or 'permissions' in job:
            issues.append('workflow-runner-or-permissions')
        if not 1 <= job.get('timeout-minutes', 0) <= 35:
            issues.append('workflow-timeout')
        steps = job.get('steps', [])
        if not steps or steps[0].get('uses') != CHECKOUT:
            issues.append('workflow-checkout-order')
        for step in steps:
            if 'uses' in step and (step['uses'] != CHECKOUT or step.get('with') != {'fetch-depth': 0, 'persist-credentials': False}):
                issues.append('workflow-action-or-credentials')
            # No expression interpolation into shell, privileged tokens, caches or uploads.
            if '${{' in step.get('run', '') or 'env' in step:
                issues.append('workflow-shell-input')
        if 'secrets' in json.dumps(job).lower() or 'environment' in job:
            issues.append('workflow-privileged-context')
    commands = {name: '\n'.join(step.get('run', '') for step in job.get('steps', [])) for name, job in jobs.items()}
    required = {
        'repository': ['python3 -m unittest discover -s Tools/CI/tests -v',
                       'python3 -m unittest discover -s Tools/OfflineQuality -v',
                       'python3 Tools/CI/repository_checks.py'],
        'macos': ['python3 Tools/CI/run_checks.py ' + action for action in
                  ['preflight', 'test', 'debug', 'release', 'concurrency', 'model-lab']],
    }
    for name, required_commands in required.items():
        if any(command not in commands.get(name, '').splitlines() for command in required_commands):
            issues.append('workflow-required-check-missing')
    mac = jobs.get('macos', {})
    if mac.get('env') != {'DEVELOPER_DIR': '/Applications/Xcode_27.0.app/Contents/Developer'} or mac.get('needs') != 'repository':
        issues.append('workflow-toolchain-or-order')
    return issues


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    issues = []
    paths = [p.decode() for p in git('ls-files', '-z').split(b'\0') if p]
    for name in paths:
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            issues.append('tracked-file-type')
            continue
        data = path.read_bytes()
        if artifact(name, len(data)):
            issues.append('tracked-artifact-or-size')
        issues.extend(secret_kinds(data))
    # Scan every reachable commit/blob, not only the worktree. Values never enter output.
    objects = {line.split()[0] for line in git('rev-list', '--objects', '--all').splitlines()}
    for oid in objects:
        kind = git('cat-file', '-t', oid.decode()).strip()
        if kind in (b'blob', b'commit'):
            issues.extend(secret_kinds(git('cat-file', '-p', oid.decode())))
    license_text = (ROOT / 'LICENSE').read_text()
    if not all(s in license_text for s in ['MIT License', 'Copyright (c) 2026 KOTHAPALLI AKSHAY WESLEY', 'Permission is hereby granted', 'THE SOFTWARE IS PROVIDED "AS IS"']):
        issues.append('root-license')
    sources = json.loads((ROOT / 'ModelLab/provenance/SOURCES.json').read_text())
    for item in sources['files']:
        if hashlib.sha256((ROOT / 'ModelLab/provenance' / item['path']).read_bytes()).hexdigest() != item['sha256']:
            issues.append('upstream-notice-or-provenance')
    research = ROOT / 'ModelLab/provenance/milestone30'
    metadata = json.loads((research / 'SOURCES.json').read_text())
    for item in metadata['sources']:
        name = item['file']
        if Path(name).name != name or name in {'.', '..'}:
            issues.append('research-provenance-path')
        elif hashlib.sha256((research / name).read_bytes()).hexdigest() != item['sha256']:
            issues.append('research-upstream-provenance')
    for required in ['THIRD_PARTY_NOTICES.md', 'Docs/Phase1B/Contracts/OpenCode-1.18.25/LICENSE',
                     'ModelLab/provenance/MLX-LM-LICENSE', 'ModelLab/provenance/upstream-LICENSE',
                     'ModelLab/provenance/model-lab2a/upstream-LICENSE.txt',
                     'ModelLab/provenance/milestone30/qwen3-LICENSE']:
        if not (ROOT / required).is_file():
            issues.append('required-notice')
    try:
        issues.extend(workflow_issues(workflow_data(ROOT / '.github/workflows/ci.yml')))
    except (ValueError, OSError, subprocess.SubprocessError):
        issues.append('workflow-syntax')
    for command in [['git', 'diff', '--check', 'HEAD'], ['git', 'show', '--format=', '--check', 'HEAD']]:
        if subprocess.run(command, cwd=ROOT, capture_output=True).returncode:
            issues.append('diff-whitespace')
    print(json.dumps({'result': 'FAILED' if issues else 'PASSED', 'trackedFiles': len(paths),
                      'historyObjects': len(objects), 'issueCategories': sorted(set(issues))}))
    return bool(issues)


if __name__ == '__main__':
    sys.exit(main())
