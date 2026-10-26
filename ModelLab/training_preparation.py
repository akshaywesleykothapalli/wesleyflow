"""Inspect installed training interfaces and materialize data/config only. Never trains."""
import ast,importlib.metadata,json,subprocess,sys
from pathlib import Path
import lab
from evaluation import local_path,offline_probe,prepared_matches

def main():
    lab.verify_runtime();proof=offline_probe();config=lab.validate_config(lab.read_json(lab.ROOT/'config/smoke.json'))
    model=local_path(lab.ROOT/'artifacts/base','model');pin=lab.read_json(lab.ROOT/'config/model-pin.json');identity=lab.verify_model(model,pin)
    dist=importlib.metadata.distribution('mlx-lm');source=Path(dist.locate_file('mlx_lm/lora.py'));tree=ast.parse(source.read_text())
    defaults=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='CONFIG_DEFAULTS' for t in n.targets))
    prepared=lab.read_json(lab.ROOT/'prepared/manifest.json');prepared_matches(prepared,lab.read_json(lab.ROOT/'config/dataset-v1.json'))
    for split,item in prepared['splits'].items():
        if lab.digest((lab.ROOT/'prepared'/(split+'.jsonl')).read_bytes())!=item['sha256']:raise lab.LabError('prepared training split changed')
    chosen={k:v for k,v in config.items() if k in defaults};chosen.update(model=str(model),data=str(lab.ROOT/'prepared'),adapter_path=str(lab.ROOT/'runs/FUTURE-APPROVED-RUN/adapter'),train=True,test=False,trust_remote_code=False,report_to=None)
    if not set(chosen)<=set(defaults):raise lab.LabError('unsupported training configuration keys')
    command=['/usr/bin/sandbox-exec','-f',str(lab.ROOT/'config/offline-worker.sb'),sys.executable,'-m','mlx_lm','lora','--help']
    result=subprocess.run(command,text=True,capture_output=True,timeout=30,env={'PATH':'/usr/bin:/bin','HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1','HF_DATASETS_OFFLINE':'1','HF_HUB_DISABLE_IMPLICIT_TOKEN':'1'})
    if result.returncode!=0 or '--grad-checkpoint' not in result.stdout:raise lab.LabError('installed training CLI unavailable')
    lab.write_json(lab.ROOT/'config/lora-smoke-v1.json',chosen)
    report={'state':'TRAINING PREPARATION VERIFIED','trainingStarted':False,'modelIdentity':identity,'packageVersion':importlib.metadata.version('mlx-lm'),'CLI':{'argv':command,'exitCode':result.returncode,'stdout':result.stdout,'stderr':result.stderr},'officialSourceSHA256':lab.digest(source.read_bytes()),'configSHA256':lab.digest((lab.ROOT/'config/lora-smoke-v1.json').read_bytes()),'sourceConfig':str(lab.ROOT/'config/smoke.json'),'datasetManifest':lab.read_json(lab.ROOT/'config/dataset-v1.json'),'adapterConvention':'runs/<owned-run-id>/adapter/adapters.safetensors plus hash-bound adapter_config.json and adapter-manifest.json','seed':42,'steps':4,'deadlineSeconds':120,'trainingAdmission':lab.admission(lab.sample(),pin['weightBytes'],True),'requires':'Separate authorization, successful full frozen baseline and fresh higher training admission; a one-case smoke is insufficient.','networkProof':proof}
    lab.write_json(lab.ROOT/'artifacts/training-preparation-v1.json',report);lab.write_json(lab.ROOT.parent/'Evidence/ModelLabReadiness/training-preparation.json',report)
    print(json.dumps({k:v for k,v in report.items() if k not in ['CLI','datasetManifest','networkProof']},indent=2))
if __name__=='__main__':main()
