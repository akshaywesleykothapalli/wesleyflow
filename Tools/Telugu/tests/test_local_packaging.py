import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('local_packaging', Path(__file__).resolve().parents[1] / 'prepare_local_app.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class LocalPackagePolicyTests(unittest.TestCase):
    def test_exception_preserves_existing_entitlements_and_input(self):
        original = {'com.apple.security.device.audio-input': True, 'com.apple.security.automation.apple-events': True}
        result = packaging.local_entitlements(original)
        self.assertNotIn('com.apple.security.cs.disable-library-validation', original)
        self.assertEqual(set(result) - set(original), {'com.apple.security.cs.disable-library-validation'})
        self.assertTrue(result['com.apple.security.cs.disable-library-validation'])
        self.assertTrue(all(result[k] == v for k, v in original.items()))

    def test_unexpected_package_cannot_gain_exception(self):
        with self.assertRaises(ValueError):
            packaging.local_entitlements({})

    def test_normally_signed_distribution_is_rejected_before_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'Source.app'
            (source / 'Contents').mkdir(parents=True)
            (source / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.wesleyflow.WesleyFlow'}))
            destination = root / 'Local.app'
            signature = subprocess.CompletedProcess([], 0, '', 'Authority=Developer ID Application: Example\nTeamIdentifier=EXAMPLE123\n')
            with patch.object(packaging.subprocess, 'run', return_value=signature) as run:
                with self.assertRaises(ValueError):
                    packaging.prepare(source, destination)
                self.assertEqual(run.call_count, 1)
            self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()
