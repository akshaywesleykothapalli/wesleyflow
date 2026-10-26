import copy,json,sys,tempfile,unittest,types
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import lab,evaluation,runner

class LocalArtifactTests(unittest.TestCase):
    def test_reject_hub_and_url(self):
        for p in ['org/model','https://huggingface.co/org/model','file:///tmp/model','../model']:
            with self.subTest(path=p),self.assertRaises(lab.LabError):evaluation.local_path(p,'model')
    def test_accept_explicit_local_folder(self):
        with tempfile.TemporaryDirectory() as d:self.assertEqual(evaluation.local_path(str(Path(d).resolve()),'model'),Path(d).resolve())
    def test_symlink_path_denied(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();link=root/'link';link.symlink_to(root)
            with self.assertRaises(lab.LabError):evaluation.local_path(link,'model')
    def test_missing_path_exact(self):
        with self.assertRaisesRegex(lab.LabError,'missing local model:'):evaluation.local_path('/nonexistent-wesleyflow-model','model')
    def test_missing_files_exact(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(lab.LabError,'missing model files: config.json, model.safetensors'):
                lab.verify_model(Path(d),{'files':[{'path':'config.json'},{'path':'model.safetensors'}]})
    def test_network_profile_fixed(self):
        command=evaluation.offline_command(lab.ROOT/'mlx_worker.py',lab.ROOT/'config/smoke.json')
        self.assertEqual(command[0],'/usr/bin/sandbox-exec');self.assertIn('-f',command);self.assertEqual(command[-2],str(lab.ROOT/'mlx_worker.py'))
    def test_no_network_fallback_if_profile_unavailable(self):
        with patch.object(Path,'read_text',return_value='(allow network*)'):
            with self.assertRaises(lab.LabError):evaluation.offline_command('worker','request')
    def test_metadata_architecture_mismatch(self):
        with patch.object(lab,'verify_model',return_value={}),patch.object(lab,'read_json',return_value={'quantization':{'bits':8}}):
            with self.assertRaises(lab.LabError):evaluation.model_metadata(Path('/fixture'),{})

class FrozenDatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl');cls.manifest=lab.read_json(lab.ROOT/'config/dataset-v1.json')
    def test_versioned_manifest_real_validator(self):
        rows,manifest,report=evaluation.versioned_dataset(lab.ROOT/'data/corpus.jsonl',lab.ROOT/'config/dataset-v1.json')
        self.assertEqual(len(rows),60);self.assertEqual(report['splits'],{'train':36,'valid':12,'test':12});self.assertEqual(manifest['corpusFingerprint'],lab.digest(rows))
    def test_preparation_exactly_reproducible(self):
        first=lab.prepare(self.rows);second=lab.prepare(self.rows);evaluation.prepared_matches(first,self.manifest);self.assertEqual(first,second)
    def test_manifest_tamper_rejected(self):
        modified=copy.deepcopy(self.manifest);modified['evaluationFingerprint']='0'*64
        with self.assertRaises(lab.LabError):evaluation.prepared_matches(modified,self.manifest)
    def test_smoke_is_exactly_one_frozen_case(self):
        selected=evaluation.select_cases(self.rows,'smoke');self.assertEqual([r['id'] for r in selected],['ml1-011']);self.assertEqual(selected[0]['split'],'test')
    def test_full_evaluation_is_held_out_only(self):self.assertEqual([r['id'] for r in evaluation.select_cases(self.rows,'baseline')],self.manifest['splits']['test']['ids'])
    def test_no_eligible_smoke_case(self):
        with self.assertRaises(lab.LabError):evaluation.select_cases([], 'smoke')

class GenerationTests(unittest.TestCase):
    def setUp(self):self.c=lab.validate_config(lab.read_json(lab.ROOT/'config/smoke.json'))
    def response(self,text,count):return types.SimpleNamespace(text=text,generation_tokens=count)
    def test_empty_stream_not_success(self):
        with self.assertRaisesRegex(lab.LabError,'no generated tokens'):evaluation.bounded_generate(iter([]),self.c)
    def test_bounded_output_and_true_timing(self):
        times=iter([0,1,2,3]);stream=iter([self.response('',1),self.response('hello',2)])
        text,m=evaluation.bounded_generate(stream,self.c,clock=lambda:next(times),memory=lambda:{'observedActiveBytes':12})
        self.assertEqual(text,'hello');self.assertEqual(m['timeToFirstTokenSeconds'],1);self.assertEqual(m['timeToFirstTextSeconds'],2);self.assertEqual(m['generationSeconds'],3);self.assertEqual(m['generatedTokens'],2)
    def test_oversized_text_rejected(self):
        with self.assertRaisesRegex(lab.LabError,'response-size'):
            evaluation.bounded_generate(iter([self.response('x'*65537,1)]),self.c)
    def test_output_token_cap_rejected(self):
        with self.assertRaises(lab.LabError):evaluation.bounded_generate(iter([self.response('x',321)]),self.c)
    def test_invalid_counter_rejected(self):
        with self.assertRaises(lab.LabError):evaluation.bounded_generate(iter([self.response('x',True)]),self.c)
    def test_deadline_deterministic(self):
        times=iter([0,120])
        with self.assertRaisesRegex(lab.LabError,'deadline'):evaluation.bounded_generate(iter([self.response('x',1)]),self.c,clock=lambda:next(times))
    def test_stream_closed_on_overflow(self):
        closed=[]
        def stream():
            try:yield self.response('x'*65537,1)
            finally:closed.append(True)
        with self.assertRaises(lab.LabError):evaluation.bounded_generate(stream(),self.c)
        self.assertEqual(closed,[True])
    def test_context_cap_before_model_load(self):
        t=types.SimpleNamespace(apply_chat_template=lambda *a,**k:list(range(800)))
        row=lab.jsonl(lab.ROOT/'data/corpus.jsonl')[0]
        with self.assertRaisesRegex(lab.LabError,'context budget'):evaluation.input_budget(t,row,self.c)
    def test_metrics_mark_unsupported_absent(self):self.assertEqual(evaluation.memory_metrics(types.SimpleNamespace()),{})

class RunnerGateTests(unittest.TestCase):
    def test_admission_failed_never_launches(self):
        with patch.object(lab,'sample',return_value={}),patch.object(lab.subprocess,'Popen',side_effect=AssertionError('no worker permitted')):
            result=lab.heavy('smoke',[],{'weightBytes':868628559,'acquisitionApproved':True},{})
        self.assertEqual(result['state'],'BLOCKED');self.assertFalse(result['adapterProduced'])
    def test_admitted_fake_worker_is_reaped_and_one_case_selected(self):
        rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl');captured=[]
        obs={'availableBytes':8*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0}
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();model=root/'base';model.mkdir();(root/'runs').mkdir();(root/'artifacts').mkdir();(root/'artifacts/runtime-verification.json').write_text('{}')
            def spawn(argv,**kwargs):
                request=Path(argv[-1]);captured.append(lab.read_json(request));lab.write_json(request.parent/'result.json',{'state':'SIMULATED','adapterProduced':False})
                return types.SimpleNamespace(returncode=0,pid=99999,poll=lambda:0)
            with patch.object(lab,'ROOT',root),patch.object(lab,'sample',return_value=obs),patch.object(lab,'verify_model',return_value={}),patch.object(lab,'verify_runtime',return_value={}),patch.object(lab,'prepare',return_value={'evaluationFingerprint':'fixture'}),patch.object(evaluation,'offline_probe',return_value={'fixture':True}),patch.object(evaluation,'offline_command',side_effect=lambda w,p:['/fixed-fixture-worker',str(p)]),patch.object(lab.subprocess,'Popen',side_effect=spawn):
                result=lab.heavy('smoke',rows,{'weightBytes':868628559,'acquisitionApproved':True},{'deadline_seconds':120},model_path=model)
            self.assertTrue(result['cleanup']['workerReaped']);self.assertEqual(result['state'],'SIMULATED');self.assertEqual(captured[0]['testIDs'],['ml1-011'])
    def test_cancel_during_worker_launch_is_caught(self):
        import signal
        rows=lab.jsonl(lab.ROOT/'data/corpus.jsonl');obs={'availableBytes':8*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0}
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();model=root/'base';model.mkdir();(root/'runs').mkdir();(root/'artifacts').mkdir();(root/'artifacts/runtime-verification.json').write_text('{}')
            proc=types.SimpleNamespace(returncode=None,pid=99999);proc.poll=lambda:proc.returncode
            def spawn(*a,**k):
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM,None)
                return proc
            def reap(p):p.returncode=-15
            with patch.object(lab,'ROOT',root),patch.object(lab,'sample',return_value=obs),patch.object(lab,'verify_model',return_value={}),patch.object(lab,'verify_runtime',return_value={}),patch.object(lab,'prepare',return_value={}),patch.object(evaluation,'offline_probe',return_value={}),patch.object(evaluation,'offline_command',side_effect=lambda w,p:['/fixed-fixture-worker',str(p)]),patch.object(lab.subprocess,'Popen',side_effect=spawn),patch.object(lab,'terminate_owned',side_effect=reap):
                result=lab.heavy('smoke',rows,{'weightBytes':868628559,'acquisitionApproved':True},{'deadline_seconds':120},model_path=model)
            self.assertEqual(result['state'],'BLOCKED');self.assertEqual(result['reason'],'cancelled');self.assertTrue(result['cleanup']['workerReaped'])
    def test_simulated_admission_success(self):
        obs={'availableBytes':8*lab.GIB,'swapUsedBytes':0,'compressorBytes':0,'diskFreeBytes':30*lab.GIB,'pressureNormal':True,'residentOllamaModels':0}
        self.assertTrue(lab.admission(obs,868628559)['admitted']);self.assertFalse(lab.admission(obs,868628559,True)['admitted'])
    def test_runner_has_no_training_mode(self):
        with self.assertRaises(lab.LabError):runner.run('/model','/data','/manifest','train')
    def test_invalid_path_fails_before_inference(self):
        with patch.object(lab,'heavy',side_effect=AssertionError('no load')):
            with self.assertRaises(lab.LabError):runner.run('hub/model','/data','/manifest','smoke')
    def test_safe_process_argv_never_uses_response(self):
        import ast
        for file in ['runner.py','evaluation.py','mlx_worker.py']:
            tree=ast.parse((lab.ROOT/file).read_text())
            for node in ast.walk(tree):
                if isinstance(node,ast.Call) and isinstance(node.func,ast.Name):self.assertNotIn(node.func.id,['eval','exec'])
                if isinstance(node,ast.keyword) and node.arg=='shell':self.assertFalse(node.value.value)

if __name__=='__main__':unittest.main()
