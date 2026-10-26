import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import lab,calibration as c

class CalibrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl');cls.row=cls.rows[0]
    def evaluate_mutation(self,change):
        proposal=copy.deepcopy(self.row['expectedProposal']);change(proposal)
        return c.evaluate(self.row,lab.canonical(proposal))
    def test_all_signatures_reproduce(self):
        saved=lab.read_json(lab.ROOT/'config/evaluation-signatures-v1.json')
        self.assertEqual(saved['cases'],[c.signature(r) for r in self.rows]);self.assertEqual(saved['corpusFingerprint'],lab.digest(self.rows))
    def test_sixty_case_audit(self):
        signatures=[c.signature(r) for r in self.rows]
        self.assertEqual(len(signatures),60);self.assertEqual(sum(bool(s['missingContract']) for s in signatures),48)
        self.assertEqual(sum(s['refusalSHA256'] is not None for s in signatures),12)
        self.assertFalse(any(s['semanticCodingEligible'] for s in signatures))
    def test_content_signature_bytes(self):
        s=c.signature(self.row)['changes'][0];raw=self.row['expectedProposal']['changes'][0]['utf8Content'].encode()
        self.assertEqual(s['contentSHA256'],lab.digest(raw));self.assertEqual(s['contentBytes'],len(raw))
    def test_valid_reference_not_semantic_success(self):
        out=c.evaluate(self.row,self.row['expectedResponse'])
        self.assertTrue(out['exactReferenceMatch']);self.assertTrue(out['validatorAccepted'])
        self.assertIsNone(out['overallTaskSuccess']);self.assertIsNone(out['semanticCodingCorrect'])
    def test_valid_json_wrong_content_cannot_pass(self):
        out=self.evaluate_mutation(lambda p:p['changes'][0].update(utf8Content='wrong'))
        self.assertTrue(out['jsonValidity']);self.assertTrue(out['schemaValidity']);self.assertTrue(out['validatorAccepted'])
        self.assertFalse(out['contentReferenceCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_project_identity(self):
        out=self.evaluate_mutation(lambda p:p.update(projectID='00000000-0000-0000-0000-000000000000'))
        self.assertFalse(out['projectIdentityCorrect']);self.assertFalse(out['validatorAccepted'])
    def test_proposal_identity(self):
        out=self.evaluate_mutation(lambda p:p.update(proposalID='00000000-0000-0000-0000-000000000000'))
        self.assertFalse(out['proposalIdentityCorrect']);self.assertFalse(out['exactReferenceMatch'])
    def test_snapshot_identity(self):
        out=self.evaluate_mutation(lambda p:p.update(baseSnapshotDigest='0'*64));self.assertFalse(out['snapshotIdentityCorrect']);self.assertFalse(out['validatorAccepted'])
    def test_target_identity(self):
        out=self.evaluate_mutation(lambda p:p['changes'][0].update(relativePath='Secrets.swift'));self.assertFalse(out['targetPathCorrect']);self.assertFalse(out['validatorAccepted'])
    def test_operation(self):
        out=self.evaluate_mutation(lambda p:p['changes'][0].update(kind='delete'));self.assertFalse(out['operationCorrect']);self.assertFalse(out['validatorAccepted'])
    def test_revision(self):
        out=self.evaluate_mutation(lambda p:p['changes'][0].update(expectedRevision={'kind':'sha256','digest':'0'*64}));self.assertFalse(out['expectedRevisionCorrect']);self.assertFalse(out['validatorAccepted'])
    def test_garbage_not_safe_refusal(self):
        out=c.evaluate(self.rows[-1],'garbage');self.assertTrue(out['validatorRejected']);self.assertFalse(out['unauthorizedOperationRejection']);self.assertFalse(out['overallTaskSuccess'])
    def test_literal_refusal(self):
        row=self.rows[-1];out=c.evaluate(row,row['expectedResponse']);self.assertTrue(out['overallTaskSuccess']);self.assertFalse(out['schemaValidity']);self.assertIsNone(out['targetPathCorrect'])
    def test_duplicate_json_keys_not_accepted(self):
        out=c.evaluate(self.row,'{"schemaVersion":1,"schemaVersion":2}');self.assertFalse(out['schemaValidity']);self.assertFalse(out['exactReferenceMatch'])
    def test_fixture_does_not_modify_original(self):
        before=lab.digest(self.rows);fixture=c.fully_specified_fixture(self.row)
        self.assertEqual(lab.digest(self.rows),before);self.assertFalse(fixture['addedToTraining']);self.assertEqual(fixture['promptRow']['expectedResponse'],self.row['expectedResponse'])
        self.assertIn(lab.canonical(self.row['expectedProposal']['changes'][0]['utf8Content']),fixture['promptRow']['instruction'])
    def test_no_heldout_fixture_rewrite(self):
        with self.assertRaises(lab.LabError):c.fully_specified_fixture(next(r for r in self.rows if r['split']=='test'))
    def test_reserves_unchanged_all_profiles(self):
        for p in c.profiles():
            self.assertEqual(p['runtimeAllowanceBytes'],2*1024**3);self.assertEqual(p['hostReserveBytes'],4*1024**3)
            self.assertEqual(p['sessions'],1);self.assertEqual(p['simultaneousModels'],1);self.assertIsNone(p['draftModel']);self.assertFalse(p['persistentPromptCache']);self.assertFalse(p['runtimeIntegrated'])
    def test_kv_payload_not_admission_discount(self):
        config={'num_hidden_layers':28,'num_key_value_heads':2,'hidden_size':1536,'num_attention_heads':12}
        p=c.profiles();est=[c.kv_estimate(x,config) for x in p]
        self.assertEqual([x['logicalKVBytes'] for x in est],[29360128,22020096,14680064]);self.assertEqual(est[1]['rotatingUnclippedTokenBound'],831)
        self.assertTrue(all(x['appliedAdmissionSavingsBytes']==0 for x in est));self.assertTrue(all(x['empiricalPeakBytes'] is None for x in est))
    def test_frozen_corpus_still_bound(self):
        lab.verify_corpus(self.rows,lab.read_json(lab.ROOT/'config/dataset-v1.json'))
    def test_all_sixty_oracle_scores(self):
        for row in self.rows:
            with self.subTest(case=row['id']):
                out=c.evaluate(row,row['expectedResponse']);self.assertTrue(out['exactReferenceMatch'])
                self.assertEqual(out['overallTaskSuccess'],None if row['expectedProposal'] else True)

if __name__=='__main__':unittest.main()
