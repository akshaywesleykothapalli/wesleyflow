import copy
import unittest
from score import score


class ScoringTests(unittest.TestCase):
    def setUp(self):
        self.data = {'version': 2, 'cases': [{'id': 'case', 'text': 'hello', 'kind': 'polish', 'needsImprovement': False}]}
        self.record = {'caseID': 'case', 'tone': 'natural', 'kind': 'polish', 'input': 'hello', 'status': 'unchanged', 'wallSeconds': 1, 'actualMaskedModelOutput': 'hello'}

    def test_appropriate_unchanged_is_not_failure(self):
        result = score(self.data, [self.record])
        self.assertEqual(result['results'][0]['unchangedAssessment'], 'appropriate-unchanged')
        self.assertEqual(result['validOutputRate'], 1)
        self.assertIsNone(result['results'][0]['meaning'])

    def test_unchanged_needing_improvement_requires_review(self):
        self.data['cases'][0]['needsImprovement'] = True
        self.assertEqual(score(self.data, [self.record])['results'][0]['unchangedAssessment'], 'needs-review-missed-improvement')

    def test_blocked_is_not_generation_or_quality_failure(self):
        self.record.update(status='resourceBlocked', actualMaskedModelOutput=None)
        result = score(self.data, [self.record])
        self.assertEqual(result['resourceBlockedRate'], 1)
        self.assertEqual(result['generated'], 0)
        self.assertIsNone(result['validOutputRate'])

    def test_invalid_raw_response_is_not_valid(self):
        self.record['status'] = 'invalidOutput'
        result = score(self.data, [self.record])
        self.assertEqual(result['generated'], 1)
        self.assertEqual(result['validOutputRate'], 0)

    def test_mismatch_and_duplicate_rejected(self):
        wrong = copy.deepcopy(self.record); wrong['input'] = 'another input'
        with self.assertRaises(ValueError): score(self.data, [wrong])
        with self.assertRaises(ValueError): score(self.data, [self.record, self.record])

    def test_empty_results_are_not_zero_percent_success(self):
        result = score(self.data, [])
        self.assertIsNone(result['validOutputRate']); self.assertIsNone(result['resourceBlockedRate'])


if __name__ == '__main__':
    unittest.main()
