import copy
from pathlib import Path
import sys
import unittest
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import repository_checks as checks
import run_checks as runner


class RepositoryChecksTests(unittest.TestCase):
    def test_workflow_parses_and_security_contract_passes(self):
        self.assertEqual(checks.workflow_issues(checks.workflow_data(checks.ROOT / '.github/workflows/ci.yml')), [])

    def test_privileged_changes_fail(self):
        original = checks.workflow_data(checks.ROOT / '.github/workflows/ci.yml')
        mutations = [lambda w: w.update(permissions={'contents': 'write'}),
                     lambda w: w['on'].update(pull_request_target={}),
                     lambda w: w['jobs']['repository']['steps'][0]['with'].update({'persist-credentials': True}),
                     lambda w: w['jobs']['repository']['steps'][0].update(uses='actions/checkout@main'),
                     lambda w: w['jobs']['macos'].update({'runs-on': 'self-hosted'}),
                     lambda w: w['jobs']['macos'].update(environment='production'),
                     lambda w: w['jobs']['macos']['steps'].append({'run': 'echo ${{ github.event.pull_request.title }}'})]
        for mutation in mutations:
            with self.subTest(change=mutations.index(mutation)):
                value = copy.deepcopy(original)
                mutation(value)
                self.assertTrue(checks.workflow_issues(value))

    def test_secret_values_are_detected(self):
        values = [('github-token', 'ghp_' + 'a' * 36), ('private-key', '-----BEGIN ' + 'PRIVATE KEY-----'),
                  ('provider-token', 'sk-' + 'x' * 40), ('aws-access', 'AKIA' + 'A' * 16),
                  ('literal-bearer', 'Bearer ' + 'x' * 40),
                  ('credential-assignment', 'password = "' + 'x' * 20 + '"')]
        for category, value in values:
            with self.subTest(category=category):
                self.assertIn(category, checks.secret_kinds(value.encode()))

    def test_negative_fixture_is_not_a_filename_wide_exemption(self):
        original = (checks.ROOT / 'Packages/WesleyFlowCore/Tests/WorkspaceTests/ContextObservationTests.swift').read_bytes()
        self.assertEqual(checks.secret_kinds(original), [])
        self.assertIn('private-key', checks.secret_kinds(original + b'\nchanged'))
        self.assertIn('github-token', checks.secret_kinds(original + ('ghp_' + 'a' * 36).encode()))

    def test_artifacts_fail_but_sources_and_synthetic_data_pass(self):
        for path in ['DerivedData/a', 'Evidence/results.json', '.env', 'ModelLab/.venv/bin/python', 'weights.safetensors', 'signing.p12', 'history.sqlite']:
            self.assertTrue(checks.artifact(path, 20), path)
        for path in ['App/AppComposition.swift', 'ModelLab/data/corpus-v2.jsonl', 'ModelLab/tests/fixtures/v2-prepared/test.jsonl', 'LICENSE']:
            self.assertFalse(checks.artifact(path, 20), path)
        self.assertTrue(checks.artifact('large.txt', 6 * 1024 * 1024))


class BuildPlanTests(unittest.TestCase):
    def test_only_four_gui_methods_are_excluded(self):
        command = runner.xcode_command('test', Path('/tmp/synthetic'))
        skips = [arg for arg in command if arg.startswith('-skip-testing:')]
        self.assertEqual(len(skips), 4)
        self.assertTrue(all(arg.endswith('()') for arg in skips))
        self.assertTrue(all(arg.startswith('-skip-testing:WesleyFlowAppTests/') for arg in skips))
        self.assertNotIn('-only-testing', ' '.join(command))
        self.assertIn('test', command)
        self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')

    def test_silent_xcode_filter_failure_is_not_success(self):
        method = runner.MANUAL_TESTS[0]
        self.assertTrue(runner.gui_executed({'children': [{'nodeIdentifier': method, 'result': 'Passed'}]}))
        self.assertFalse(runner.gui_executed({'children': [{'nodeIdentifier': method, 'result': 'Skipped'}]}))
        self.assertFalse(runner.gui_executed({'children': [{'nodeIdentifier': 'Other/test()', 'result': 'Passed'}]}))

    def test_build_modes_and_complete_concurrency(self):
        for action, configuration in [('debug', 'Debug'), ('release', 'Release'), ('concurrency', 'Release')]:
            command = runner.xcode_command(action, Path('/tmp/synthetic'))
            self.assertEqual(command[command.index('-configuration') + 1], configuration)
            self.assertEqual(command[-1], 'build')
            self.assertEqual('SWIFT_STRICT_CONCURRENCY=complete' in command, action == 'concurrency')
            self.assertIn('-disableAutomaticPackageResolution', command)

    def test_version_parser_rejects_unknown(self):
        self.assertEqual(runner.version('Apple Swift version 6.4 (build)'), (6, 4))
        with self.assertRaises(ValueError):
            runner.version('unavailable')


class IntegratedRegressionGateTests(unittest.TestCase):
    def summary(self, cases=1374):
        return {'devicesAndConfigurations':[{'passedTests':cases}], 'failedTests':0, 'result':'Passed'}

    def tree(self):
        return {'children':[{'nodeIdentifier':name, 'result':'Passed'} for name in runner.REQUIRED_APP_TESTS]}

    def test_old_floor_is_not_current_coverage(self):
        with self.assertRaises(ValueError):
            runner.require_test_results(self.summary(1335), self.tree())
        self.assertEqual(runner.require_test_results(self.summary(), self.tree()), 1374)

    def test_enough_cases_cannot_hide_missing_or_skipped_new_regression(self):
        tree = self.tree()
        tree['children'][0]['result'] = 'Skipped'
        with self.assertRaises(ValueError):
            runner.require_test_results(self.summary(2000), tree)
        with self.assertRaises(ValueError):
            runner.require_test_results(self.summary(2000), {'children':[]})

    def test_integrated_checks_cannot_be_removed_from_workflow(self):
        original = checks.workflow_data(checks.ROOT / '.github/workflows/ci.yml')
        for lane in ['repository', 'macos']:
            value = copy.deepcopy(original)
            value['jobs'][lane]['steps'] = value['jobs'][lane]['steps'][:1]
            self.assertIn('workflow-required-check-missing', checks.workflow_issues(value))

    def test_gui_exclusions_still_reject_accidental_execution(self):
        tree = self.tree()
        tree['children'].append({'nodeIdentifier':runner.MANUAL_TESTS[0], 'result':'Passed'})
        with self.assertRaises(ValueError):
            runner.require_test_results(self.summary(), tree)


if __name__ == '__main__':
    unittest.main()


class FailureDiagnosticsTests(unittest.TestCase):
    def test_source_locations_are_useful_without_leaking_diagnostics(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'build.log'
            private='PRIVATE_FIXTURE_CONTENT'
            log.write_text('/private/user/project/App.swift:42:7: error: type has no member '+private+'\n'+private+'\n')
            result=runner.failure_diagnostics(log)
            self.assertEqual(result['sourceLocations'],[{'file':'App.swift','line':42}])
            self.assertEqual(result['categories'],['swift-missing-symbol'])
            self.assertNotIn(private,str(result))
            self.assertNotIn('/private/user',str(result))

    def test_build_commands_pin_the_verified_apple_silicon_lane(self):
        for action in ['test','debug','release','concurrency']:
            command=runner.xcode_command(action,Path('/tmp/synthetic'))
            self.assertIn('ARCHS=arm64',command)
            self.assertIn('ONLY_ACTIVE_ARCH=YES',command)
            self.assertIn('DEBUG_INFORMATION_FORMAT=dwarf',command)
