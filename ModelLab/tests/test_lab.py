import ast, copy, hashlib, json, os, struct, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import lab

class CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl')
    def test_production_targets(self):
        report=lab.validate_rows(self.rows);self.assertEqual(report['splits'],{'train':36,'valid':12,'test':12});self.assertEqual(report['acceptedTargets'],48)
    def invalid(self,change):
        rows=copy.deepcopy(self.rows);change(rows)
        with self.assertRaises((lab.LabError,ValueError,TypeError)):lab.validate_rows(rows)
    def test_every_split_covers_both_wire_operations(self):
        for split in ['train','valid','test']:
            kinds={r['expectedProposal']['changes'][0]['kind'] for r in self.rows if r['split']==split and r['expectedProposal']}
            self.assertEqual(kinds,{'create','update'})
    def test_duplicate_identity(self):self.invalid(lambda r:r.append(copy.deepcopy(r[0])))
    def test_duplicate_task_cannot_hide_behind_new_binding(self):
        def change(rows):
            clone=copy.deepcopy(rows[0]);clone['id']='ml1-099';clone['projectID']='00000000-0000-0000-0000-000000000099';clone['expectedProposal']['projectID']=clone['projectID'];clone['expectedResponse']=lab.canonical(clone['expectedProposal']);rows.append(clone)
        self.invalid(change)
    def test_missing_field(self):self.invalid(lambda r:r[0].pop('instruction'))
    def test_unknown_field(self):self.invalid(lambda r:r[0].update(secret='x'))
    def test_invalid_split(self):self.invalid(lambda r:r[0].update(split='hidden'))
    def test_non_synthetic(self):self.invalid(lambda r:r[0]['provenance'].update(kind='user'))
    def test_long_instruction(self):self.invalid(lambda r:r[0].update(instruction='x'*1025))
    def test_target_mismatch(self):self.invalid(lambda r:r[0].update(expectedResponse='{}'))
    def test_rejection_target_requires_exact_refusal(self):self.invalid(lambda r:r[-1].update(expectedResponse='Cannot propose this request: execute rm'))
    def test_family_split_leak(self):self.invalid(lambda r:r[8].update(family=r[0]['family']))
    def test_semantic_near_duplicate_cross_split(self):
        def change(r):r[8].update(instruction=r[0]['instruction'],expectedProposal=r[0]['expectedProposal'],expectedResponse=r[0]['expectedResponse'])
        self.invalid(change)
    def test_actual_validator_catches_bad_revision(self):
        def change(r):
            target=r[1]['expectedProposal'];target['changes'][0]['expectedRevision']['digest']='0'*64;r[1]['expectedResponse']=lab.canonical(target)
        self.invalid(change)
    def test_oracle_cardinality(self):
        with self.assertRaises(lab.LabError):lab.validate_rows(self.rows,oracle=lambda _:[])
    def test_no_expected_output_in_prompt(self):
        row=self.rows[0];p=lab.prompt(row);self.assertNotIn('expectedResponse',p);self.assertNotIn(row['expectedProposal']['changes'][0]['utf8Content'],lab.canonical(p))
    def test_overflow_float_json(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x';p.write_text('{"x":1e999}')
            with self.assertRaises(lab.LabError):lab.read_json(p)
    def test_no_empty_splits(self):
        with self.assertRaises(lab.LabError):lab.validate_rows([self.rows[0]])
    def test_strict_duplicate_jsonl(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x';p.write_text('{"a":1,"a":2}\n')
            with self.assertRaises(lab.LabError):lab.jsonl(p)
    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x';p.write_text('{"x":NaN}')
            with self.assertRaises(lab.LabError):lab.read_json(p)
    def test_full_corpus_tamper_is_rejected(self):
        manifest={'corpusFingerprint':lab.digest(self.rows),'evaluationFingerprint':lab.digest([r for r in self.rows if r['split']=='test'])}
        self.assertEqual(lab.verify_corpus(self.rows,manifest),self.rows)
        changed=copy.deepcopy(self.rows);changed[0]['instruction']='tampered'
        with self.assertRaises(lab.LabError):lab.verify_corpus(changed,manifest)
    def test_preparation_cannot_race_active_lease(self):
        with lab.lease():
            with self.assertRaises(lab.LabError):lab.prepare(self.rows)
    def test_prepared_split_identity_is_stable(self):
        a=lab.prepare(self.rows);b=lab.prepare(self.rows);self.assertEqual(a,b);self.assertEqual(a['evaluationFingerprint'],lab.digest([r for r in self.rows if r['split']=='test']))

class ProductionAdversarialTests(unittest.TestCase):
    def test_rejects_each_unsafe_proposal(self):
        row=lab.jsonl(lab.ROOT/'data/corpus.jsonl')[1];cases=[]
        def add(name,mutate):
            p=copy.deepcopy(row['expectedProposal']);mutate(p);cases.append((name,lab.canonical(p)))
        add('unauthorized',lambda p:p['changes'][0].update(relativePath='Sources/Other.swift'))
        add('traversal',lambda p:p['changes'][0].update(relativePath='../Secret.swift'))
        add('absolute',lambda p:p['changes'][0].update(relativePath='/tmp/Secret.swift'))
        add('wrong-project',lambda p:p.update(projectID='00000000-0000-0000-0000-000000000000'))
        add('stale-revision',lambda p:p['changes'][0]['expectedRevision'].update(digest='0'*64))
        add('snapshot',lambda p:p.update(baseSnapshotDigest='0'*64))
        add('shell',lambda p:p.update(command='echo forbidden'))
        add('delete',lambda p:p['changes'][0].update(kind='delete'))
        add('empty',lambda p:p.update(changes=[]))
        cases.append(('duplicate-key',row['expectedResponse'].replace('"schemaVersion":1','"schemaVersion":1,"schemaVersion":1')))
        results=lab.bridge([lab.context(row,text) for _,text in cases])
        for (name,_),result in zip(cases,results):
            with self.subTest(name=name):self.assertFalse(result['accepted']);self.assertTrue(result['reasons'])
    def test_actual_safe_refusal_is_rejected_by_codec(self):
        row=lab.jsonl(lab.ROOT/'data/corpus.jsonl')[-1];out=lab.bridge([lab.context(row,row['expectedResponse'])])[0]
        self.assertFalse(out['accepted']);self.assertEqual(out['reasons'],['malformed'])

class GuardTests(unittest.TestCase):
    def setUp(self):self.obs={'availableBytes':12*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0}
    def test_separate_training_budget(self):
        self.obs['availableBytes']=8*lab.GIB;self.assertTrue(lab.admission(self.obs,lab.GIB)['admitted']);self.assertFalse(lab.admission(self.obs,lab.GIB,True)['admitted'])
    def test_reserves_preserved(self):
        d=lab.admission(self.obs,lab.GIB,True);self.assertEqual(d['requiredAvailableBytes'],10*lab.GIB);self.assertEqual(d['systemReserveBytes'],4*lab.GIB)
    def test_unknown_observation_blocks(self):self.assertFalse(lab.admission({},lab.GIB)['admitted'])
    def test_bad_model_size_blocks(self):
        for value in [None,True,-1,0,'large',3*lab.GIB]:
            with self.subTest(value=value):self.assertFalse(lab.admission(self.obs,value)['admitted'])
    def test_disk_blocks(self):self.obs['diskFreeBytes']=19*lab.GIB;self.assertFalse(lab.admission(self.obs,lab.GIB)['admitted'])
    def test_pressure_blocks(self):self.obs['pressureNormal']=False;self.assertFalse(lab.admission(self.obs,lab.GIB)['admitted'])
    def test_foreign_residency_blocks(self):
        for value in [None,False,1]:
            self.obs['residentOllamaModels']=value;self.assertFalse(lab.admission(self.obs,lab.GIB)['admitted'])
    def test_invalid_counter_blocks(self):self.obs['availableBytes']='unavailable';self.assertFalse(lab.admission(self.obs,lab.GIB)['admitted'])
    def test_swap_requires_two_samples(self):
        now={**self.obs,'swapUsedBytes':257*1024**2};reason,w=lab.stop_reason(now,self.obs,0);self.assertIsNone(reason);self.assertEqual(lab.stop_reason(now,self.obs,w)[0],'sustained-swap-growth')
    def test_swap_warning_resets(self):self.assertEqual(lab.stop_reason(self.obs,self.obs,1),(None,0))
    def test_compressor_growth(self):self.assertEqual(lab.stop_reason({**self.obs,'compressorBytes':513*1024**2},self.obs,0)[0],'compression-growth')
    def test_missing_monitor_sample(self):self.assertEqual(lab.stop_reason({},self.obs,0)[0],'observation-unavailable')
    def test_cancellation(self):
        proc=type('Proc',(),{'poll':lambda _:None})();reason,samples=lab.monitor(proc,self.obs,10,clock=lambda:0,cancelled=lambda:True);self.assertEqual(reason,'cancelled');self.assertEqual(samples,[])
    def test_deadline(self):
        proc=type('Proc',(),{'poll':lambda _:None})();self.assertEqual(lab.monitor(proc,self.obs,10,clock=lambda:10)[0],'deadline')
    def test_monitor_stops_without_sleep_on_pressure(self):
        proc=type('Proc',(),{'poll':lambda _:None})();reason,_=lab.monitor(proc,self.obs,10,sample_fn=lambda:{**self.obs,'pressureNormal':False},clock=lambda:0,wait=lambda:self.fail('no wait after stop'));self.assertEqual(reason,'memory-pressure-or-reserve')
    def test_no_worker_when_blocked(self):
        with patch.object(lab,'sample',return_value={}),patch.object(lab.subprocess,'Popen',side_effect=AssertionError('must not launch')):
            result=lab.heavy('train',[],{'weightBytes':lab.GIB},{})
        self.assertEqual(result['state'],'BLOCKED');self.assertFalse(result['adapterProduced'])
    def test_owned_shutdown_handles_process_exit_race(self):
        proc=type('Proc',(),{'pid':12345,'poll':lambda _:None,'wait':lambda _,timeout:0})()
        with patch.object(lab.os,'killpg',side_effect=ProcessLookupError):lab.terminate_owned(proc)
    def test_owned_shutdown_escalation(self):
        import subprocess,signal
        proc=type('Proc',(),{'pid':12345,'poll':lambda _:None,'wait':lambda _,timeout:0})()
        with patch.object(lab.os,'killpg') as kill:lab.terminate_owned(proc)
        self.assertEqual(kill.call_args_list[0].args,(12345,signal.SIGINT))
        self.assertTrue(all(call.args[0]==12345 for call in kill.call_args_list))
    def test_config_caps(self):
        c=lab.read_json(lab.ROOT/'config/smoke.json');self.assertEqual(lab.validate_config(c)['iters'],4)
        for field,value in [('iters',5),('seed',True),('max_seq_length',2048),('batch_size',2),('learning_rate',float('nan'))]:
            with self.subTest(field=field),self.assertRaises(lab.LabError):lab.validate_config({**c,field:value})

class ArtifactTests(unittest.TestCase):
    def test_model_digest_and_extra_file(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d);(path/'weights').write_bytes(b'test');pin={'repository':'synthetic','revision':'fixture','files':[{'path':'weights','size':4,'sha256':hashlib.sha256(b'test').hexdigest()}]}
            self.assertEqual(lab.verify_model(path,pin)['revision'],'fixture')
            (path/'extra.py').write_text('forbidden')
            with self.assertRaises(lab.LabError):lab.verify_model(path,pin)
            (path/'extra.py').unlink();(path/'weights').write_bytes(b'fail')
            with self.assertRaises(lab.LabError):lab.verify_model(path,pin)
    def test_manifest_traversal(self):
        with tempfile.TemporaryDirectory() as d,self.assertRaises(lab.LabError):lab.verify_model(d,{'files':[{'path':'../outside'}]})
    def test_symlink_model(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'link';p.symlink_to(d)
            with self.assertRaises(lab.LabError):lab.verify_model(p,{'files':[]})
    def test_simulated_adapter_manifest_and_extent(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'adapter.safetensors';header=lab.canonical({'layer.lora_a':{'dtype':'F32','shape':[1],'data_offsets':[0,4]}}).encode();p.write_bytes(struct.pack('<Q',len(header))+header+struct.pack('<f',1.0))
            manifest=lab.artifact_manifest(p,{'revision':'fixture'},{},{'corpusFingerprint':'a','evaluationFingerprint':'b'},{},simulated=True)
            self.assertEqual(manifest['state'],'SIMULATED');self.assertFalse(manifest['promoted']);self.assertEqual(manifest['adapterSHA256'],hashlib.sha256(p.read_bytes()).hexdigest())
            p.write_bytes(p.read_bytes()[:-1])
            with self.assertRaises(lab.LabError):lab.artifact_manifest(p,{}, {},{}, {},simulated=True)
    def test_no_adapter_means_no_manifest(self):
        with self.assertRaises(lab.LabError):lab.artifact_manifest('/missing/adapter',{}, {},{}, {})

class ScoringTests(unittest.TestCase):
    def setUp(self):self.rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl');self.row=self.rows[0]
    def test_correct_proposal(self):
        out=lab.bridge([lab.context(self.row,self.row['expectedResponse'])])[0];self.assertTrue(lab.score(self.row,self.row['expectedResponse'],out)['exactTaskCorrect'])
    def test_valid_schema_wrong_code_not_correct(self):
        p=copy.deepcopy(self.row['expectedProposal']);p['changes'][0]['utf8Content']='wrong';text=lab.canonical(p);out=lab.bridge([lab.context(self.row,text)])[0];self.assertTrue(out['accepted']);self.assertFalse(lab.score(self.row,text,out)['exactTaskCorrect'])
    def test_garbage_not_safe_refusal(self):
        row=self.rows[-1];self.assertFalse(lab.score(row,'bad',{'accepted':False,'reasons':['malformed']})['safeExpectedRefusal'])
    def test_expected_refusal(self):
        row=self.rows[-1];self.assertTrue(lab.score(row,row['expectedResponse'],{'accepted':False,'reasons':['malformed']})['safeExpectedRefusal'])
    def test_unauthorized_command_scored_even_if_rejected(self):self.assertTrue(lab.score(self.row,'{"commands":["forbidden"]}',{'accepted':False})['unauthorizedOperations'])
    def test_malformed_response_shapes(self):
        for response in ['null','[]','{"changes":null}','{"changes":[1]}','{']:
            with self.subTest(response=response):self.assertFalse(lab.score(self.row,response,{})['exactTaskCorrect'])
    def test_comparison_provenance(self):
        with self.assertRaises(lab.LabError):lab.comparison({'evaluationFingerprint':'a'},{'evaluationFingerprint':'b'})
    def test_comparison_never_promotes(self):
        score=lab.score(self.row,self.row['expectedResponse'],{'accepted':True,'schemaValid':True});base={'baseIdentity':{},'evaluationFingerprint':'a','settingsFingerprint':'b','scores':[score]};out=lab.comparison(base,base);self.assertFalse(out['promoted']);self.assertFalse(out['correctnessImproved'])
    def test_no_generated_code_execution_surface(self):
        for name in ['lab.py','mlx_worker.py']:
            tree=ast.parse((lab.ROOT/name).read_text())
            for node in ast.walk(tree):
                if isinstance(node,ast.Call) and isinstance(node.func,ast.Name):self.assertNotIn(node.func.id,['exec','eval'])
                if isinstance(node,ast.keyword) and node.arg=='shell':self.assertFalse(node.value.value)


class TokenShapeTests(unittest.TestCase):
    def test_explicit_list_contract(self):
        class Tokenizer:
            def apply_chat_template(self,messages,**kwargs):
                self.kwargs=kwargs;return [1,2,3]
        t=Tokenizer();self.assertEqual(lab.chat_tokens(t,[],generation=True),[1,2,3]);self.assertFalse(t.kwargs['return_dict']);self.assertTrue(t.kwargs['add_generation_prompt'])
    def test_dictionary_not_miscounted_as_two_tokens(self):
        t=type('Tokenizer',(),{'apply_chat_template':lambda *a,**k:{'input_ids':[1,2],'attention_mask':[1,1]}})()
        with self.assertRaises(lab.LabError):lab.chat_tokens(t,[])
    def test_invalid_token_shapes_rejected(self):
        for tokens in [[],[[1,2]],[-1],[True],['1']]:
            t=type('Tokenizer',(),{'apply_chat_template':lambda *a,**k:tokens})()
            with self.subTest(tokens=tokens),self.assertRaises(lab.LabError):lab.chat_tokens(t,[])

if __name__=='__main__':unittest.main()
