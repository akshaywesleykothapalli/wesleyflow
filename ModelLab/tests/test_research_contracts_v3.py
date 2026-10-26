"""Research contract tests. No model imports, Swift reference execution or training."""
import copy
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from unittest.mock import patch
import lab
import semantic_v2
import research_contracts_v3 as v3


class ResearchContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.value = v3.build()
        cls.cases = cls.value['revisions']
        cls.old = {c['id']: c for c in semantic_v2.load_frozen()[0]}

    def test_frozen_research_reproduction(self):
        self.assertEqual(v3.verify()['revisions'], 5)
        self.assertEqual(v3.verify()['eligibleForTraining'], 0)

    def test_original_version_fingerprints_unchanged(self):
        self.assertEqual(lab.read_json(lab.ROOT/'config/dataset-v1.json')['corpusFingerprint'], 'abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065')
        self.assertEqual(self.value['frozenV2Fingerprint'], '9f6a68aae503f390ea42663826bf76c53e367aa8ee305b0e3197e9578d3b7ce6')
        self.assertEqual(sum(c['status']=='INCOMPLETE' for c in self.old.values()), 5)

    def test_family_and_split_isolation(self):
        for case in self.cases:
            source = self.old[case['sourceV2ID']]
            self.assertEqual((case['split'],case['family']), (source['split'],source['family']))
            self.assertNotEqual(case['projectID'], source['projectID'])
            self.assertNotEqual(case['workspaceRevision'], source['workspaceRevision'])
        self.assertEqual(self.value['splits'], {'train':['m30-001','m30-026','m30-040'], 'valid':['m30-009'], 'test':['m30-047']})

    def test_native_references_and_four_file_context(self):
        for case in self.cases:
            self.assertEqual(len(case['projectTree']),4)
            self.assertEqual(len(case['editableTargets']),1)
            self.assertEqual(case['expectedContent'],self.old[case['sourceV2ID']]['expectedContent'])
            self.assertEqual(case['expectedProposal']['changes'][0]['kind'],case['supportedOperation'])
            self.assertTrue(case['independentValidation']['nativeStructuralValidatorAccepted'])

    def test_unapproved_context_file_is_rejected(self):
        case=self.cases[0]; proposal=copy.deepcopy(case['expectedProposal'])
        proposal['changes'][0].update(kind='update',relativePath='README.md')
        context=dict(projectID=case['projectID'],proposalID=case['proposalID'],entries=case['projectTree'],editableTargets=case['editableTargets'])
        native=lab.bridge([context])[0]
        proposal['changes'][0]['expectedRevision']=native['revisions']['README.md']
        result=lab.bridge([{**context,'response':lab.canonical(proposal)}])[0]
        self.assertTrue(result['schemaValid']); self.assertFalse(result['accepted'])

    def test_arithmetic_bounds_do_not_assume_wrapping(self):
        by_id={c['sourceV2ID']:c for c in self.cases}
        self.assertEqual(by_id['ml2a-001']['arithmeticBounds']['maximumAbsoluteResult'], 1_000_000+1_000_000)
        for key in ['ml2a-009','ml2a-040']:
            self.assertEqual(by_id[key]['arithmeticBounds']['maximumAbsoluteResult'],1_000_000**2)
        self.assertEqual(by_id['ml2a-026']['arithmeticBounds']['maximumAbsoluteResult'],999_999+1)
        self.assertEqual(by_id['ml2a-047']['arithmeticBounds']['maximumAbsoluteResult'],1_048_576)
        self.assertTrue(all(0 <= c['arithmeticBounds']['maximumAbsoluteResult'] < 2**63 for c in self.cases))

    def test_no_independent_semantic_or_training_claim(self):
        self.assertFalse(self.value['modelLoaded']); self.assertFalse(self.value['trainingStarted'])
        self.assertEqual(self.value['newIndependentTrainingExamples'],0)
        for case in self.cases:
            self.assertFalse(case['trainingEligible'])
            self.assertFalse(case['independentValidation']['referenceSwiftExecuted'])
            self.assertFalse(case['independentValidation']['independentHumanReviewed'])
            self.assertEqual(case['status'],'SPECIFIED_PENDING_INDEPENDENT_REVIEW')

    def test_research_never_samples_host_or_starts_worker(self):
        with patch.object(lab,'sample',side_effect=AssertionError('must not sample memory')), patch.object(lab,'verify_runtime',side_effect=AssertionError('must not import runtime')):
            self.assertEqual(len(v3.build()['revisions']),5)

    def test_tampering_rejected(self):
        stored=lab.read_json(lab.ROOT/'data/research-contracts-v3.json');stored['revisions'][0]['trainingEligible']=True
        original=lab.read_json
        def reader(path):
            return stored if str(path).endswith('research-contracts-v3.json') else original(path)
        with patch.object(lab,'read_json',side_effect=reader):
            with self.assertRaises(lab.LabError): v3.verify()
