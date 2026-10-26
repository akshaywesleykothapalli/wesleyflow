import copy,json,sys,unittest
from pathlib import Path
from unittest.mock import Mock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import lab,semantic_v2 as v2,build_dataset_v2 as builder

class SemanticV2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases,cls.manifest,cls.leakage=v2.load_frozen();cls.case=next(r for r in cls.cases if r['id']=='ml2a-003')
    def mutation(self,fn):
        proposal=copy.deepcopy(self.case['expectedProposal']);fn(proposal)
        return v2.semantic_score(self.case,lab.canonical(proposal))
    def test_frozen_dataset_reproduces(self):self.assertEqual(builder.build()['corpusFingerprint'],self.manifest['corpusFingerprint'])
    def test_correct_contract(self):
        out=v2.semantic_score(self.case,self.case['expectedResponse']);self.assertTrue(out['overallTaskSuccess']);self.assertTrue(out['contentAssertionsCorrect']);self.assertTrue(out['structuralContractSatisfied']);self.assertIsNone(out['behavioralRuntimeCorrect']);self.assertFalse(out['behavioralExamplesExecuted'])
    def test_all_signatures_exact(self):self.assertEqual(self.manifest['signatures'],[v2.signature(r) for r in self.cases])
    def test_wrong_target(self):
        out=self.mutation(lambda p:p['changes'][0].update(relativePath='Secrets.swift'));self.assertFalse(out['structural']['targetPathCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_operation(self):
        out=self.mutation(lambda p:p['changes'][0].update(kind='update'));self.assertFalse(out['structural']['operationCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_revision(self):
        out=self.mutation(lambda p:p['changes'][0].update(expectedRevision={'kind':'sha256','digest':'0'*64}));self.assertFalse(out['structural']['expectedRevisionCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_content_valid_structure(self):
        out=self.mutation(lambda p:p['changes'][0].update(utf8Content='func isEven(_ value: Int) -> Bool { true }\n'))
        self.assertTrue(out['structural']['validatorAccepted']);self.assertTrue(out['structural']['schemaValidity']);self.assertFalse(out['contentAssertionsCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_project(self):
        out=self.mutation(lambda p:p.update(projectID='00000000-0000-0000-0000-000000000000'));self.assertFalse(out['structural']['projectIdentityCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_snapshot(self):
        out=self.mutation(lambda p:p.update(baseSnapshotDigest='0'*64));self.assertFalse(out['structural']['snapshotIdentityCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_wrong_proposal(self):
        out=self.mutation(lambda p:p.update(proposalID='00000000-0000-0000-0000-000000000000'));self.assertFalse(out['structural']['proposalIdentityCorrect']);self.assertFalse(out['overallTaskSuccess'])
    def test_incomplete_cannot_pass(self):
        cases=[r for r in self.cases if r['status']=='INCOMPLETE'];self.assertEqual(len(cases),5)
        for case in cases:
            out=v2.semantic_score(case,case['expectedResponse']);self.assertIsNone(out['contentAssertionsCorrect']);self.assertIsNone(out['overallTaskSuccess']);self.assertTrue(case['incompleteReason'])
    def test_v1_version_untouched(self):
        original=lab.jsonl(lab.ROOT/'data/corpus.jsonl');manifest=lab.read_json(lab.ROOT/'config/dataset-v1.json');lab.verify_corpus(original,manifest)
        self.assertEqual(manifest['corpusFingerprint'],'abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065');self.assertNotEqual(manifest['evaluationFingerprint'],self.manifest['evaluationFingerprint'])
    def test_heldout_isolation(self):
        original={r['id']:r for r in lab.jsonl(lab.ROOT/'data/corpus.jsonl')}
        for case in self.cases:self.assertEqual(case['split'],original[case['sourceV1ID']]['split']);self.assertEqual(case['sourceV1RowSHA256'],lab.digest(original[case['sourceV1ID']]))
        splits=[set(self.manifest['splits'][s]['ids']) for s in ['train','valid','test']]
        self.assertFalse(splits[0]&splits[1] or splits[0]&splits[2] or splits[1]&splits[2])
    def test_refusal_is_not_garbage(self):
        case=self.cases[-1];self.assertTrue(v2.semantic_score(case,case['expectedResponse'])['rejectionCorrect']);self.assertFalse(v2.semantic_score(case,'garbage')['rejectionCorrect'])
    def test_schema_extra_field(self):
        out=self.mutation(lambda p:p.update(command='never-run'));self.assertFalse(out['structural']['schemaValidity']);self.assertFalse(out['overallTaskSuccess'])
    def test_extra_file(self):
        out=self.mutation(lambda p:p['changes'].append(copy.deepcopy(p['changes'][0])));self.assertFalse(out['overallTaskSuccess'])
    def test_malformed_changes(self):
        for changes in [None,True,1,'text',{},[None]]:
            with self.subTest(changes=changes):self.assertFalse(self.mutation(lambda p:p.update(changes=changes))['overallTaskSuccess'])
    def test_crlf_variant(self):
        case=next(r for r in self.cases if r['id']=='ml2a-016');p=copy.deepcopy(case['expectedProposal']);p['changes'][0]['utf8Content']=case['expectedContent'].replace('\n','\r\n')
        self.assertTrue(v2.semantic_score(case,lab.canonical(p))['overallTaskSuccess'])
    def test_whitespace_not_blindly_ignored(self):
        out=self.mutation(lambda p:p['changes'][0].update(utf8Content=self.case['expectedContent'].replace(' == ','== ')))
        self.assertFalse(out['approvedSourceMatch']);self.assertTrue(out['unreviewedVariant'])
    def test_changed_literal_not_equivalent(self):
        case=self.cases[-13];self.assertEqual(case['id'],'ml2a-048');p=copy.deepcopy(case['expectedProposal']);p['changes'][0]['utf8Content']=case['expectedContent'].replace('"zero"','" zero "')
        self.assertFalse(v2.semantic_score(case,lab.canonical(p))['contentAssertionsCorrect'])
    def test_dataset_tamper_denied(self):
        original=lab.read_json;path=lab.ROOT/'config/dataset-v2.json';bad=copy.deepcopy(self.manifest);bad['evaluationFingerprint']='0'*64
        with patch.object(lab,'read_json',side_effect=lambda p:bad if Path(p)==path else original(p)):
            with self.assertRaises(lab.LabError):v2.load_frozen()
    def test_no_execution_after_failed_admission(self):
        observe=Mock(return_value={'availableBytes':5*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0});execute=Mock(side_effect=AssertionError('must not execute'))
        result=v2.one_admission_gate(observe,868628559,execute);self.assertEqual(result['state'],'BLOCKED');self.assertFalse(result['executed']);observe.assert_called_once();execute.assert_not_called()
    def test_unknown_observation_blocks(self):
        execute=Mock();result=v2.one_admission_gate(lambda:{},868628559,execute);self.assertEqual(result['state'],'BLOCKED');execute.assert_not_called()
    def test_admitted_fixture_executor_once(self):
        obs={'availableBytes':8*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0};execute=Mock(return_value={'state':'FIXTURE ONLY'});observe=Mock(return_value=obs)
        self.assertEqual(v2.one_admission_gate(observe,868628559,execute)['state'],'FIXTURE ONLY');execute.assert_called_once();observe.assert_called_once()
    def test_no_unsafe_savings_for_smaller_model(self):
        small=lab.read_json(lab.ROOT/'config/model-0.5b-research-v1.json');observed=lab.read_json(Path(__file__).resolve().parent/'fixtures/blocked-admission.json')['sample'];decision=lab.admission(observed,small['weightBytes'])
        self.assertEqual(decision['systemReserveBytes'],4*lab.GIB);self.assertEqual(decision['runtimeAllowanceBytes'],2*lab.GIB);self.assertFalse(decision['admitted']);self.assertFalse(small['acquisitionApproved']);self.assertFalse(small['modelDownloaded'])
    def test_no_cross_split_coding_duplicates(self):
        self.assertFalse(self.leakage['crossSplitExactCodingDuplicates']);self.assertFalse(self.leakage['crossSplitNearDuplicates']);self.assertTrue(self.leakage['sharedRefusalTargetAcrossSplits'])
    def test_prompt_contains_no_expected_body(self):
        prompt=lab.canonical(v2.prompt(self.case));self.assertNotIn(self.case['expectedContent'],prompt);self.assertNotIn('expectedContent',prompt);self.assertIn(self.case['behaviorContract']['api'],prompt)
    def test_training_excludes_incomplete(self):
        for split in ['train','valid','test']:
            eligible=set(self.manifest['splits'][split]['eligibleIDs']);self.assertTrue(all(r['status']=='COMPLETE' for r in self.cases if r['id'] in eligible))
    def test_all_sixty_reference_scores(self):
        for case in self.cases:
            with self.subTest(case=case['id']):self.assertEqual(v2.semantic_score(case,case['expectedResponse'])['overallTaskSuccess'],None if case['status']=='INCOMPLETE' else True)
    def test_prepared_files_preserve_real_split_isolation(self):
        prepared=lab.read_json(Path(__file__).resolve().parent/'fixtures/v2-prepared/manifest.json');sets=[]
        for split in ['train','valid','test']:
            raw=(Path(__file__).resolve().parent/'fixtures/v2-prepared'/(split+'.jsonl')).read_bytes();self.assertEqual(lab.digest(raw),prepared['splits'][split]['sha256'])
            projects={json.loads(row['messages'][1]['content'])['projectID'] for row in lab.jsonl(Path(__file__).resolve().parent/'fixtures/v2-prepared'/(split+'.jsonl'))}
            expected={case['projectID'] for case in self.cases if case['split']==split and case['status']=='COMPLETE'};self.assertEqual(projects,expected);sets.append(projects)
        self.assertFalse(sets[0]&sets[1] or sets[0]&sets[2] or sets[1]&sets[2])
    def test_recorded_failed_gate_never_spawns(self):
        obs=lab.read_json(Path(__file__).resolve().parent/'fixtures/blocked-admission.json')['sample'];execute=Mock(side_effect=AssertionError('model may not run'))
        with patch.object(lab,'sample',side_effect=AssertionError('no resample')):
            result=v2.one_admission_gate(lambda:obs,868628559,execute)
        self.assertEqual(result['state'],'BLOCKED');execute.assert_not_called()
    def test_small_metadata_pin_tamper_rejected(self):
        import small_model_feasibility
        original=lab.read_json;path=lab.ROOT/'config/model-0.5b-research-v1.json';changed=copy.deepcopy(original(path));changed['revision']='0'*40
        with patch.object(lab,'read_json',side_effect=lambda p:changed if Path(p)==path else original(p)):
            with self.assertRaises(lab.LabError):small_model_feasibility.assess()

if __name__=='__main__':unittest.main()
