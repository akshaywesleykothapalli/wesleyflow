#!/usr/bin/env python3
"""Record fixed Model Lab verification commands and their actual exit codes."""
from pathlib import Path
import argparse,datetime,json,os,signal,subprocess,sys
root=Path(__file__).resolve().parent;repo=root.parent
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['tests','replay','tokenizer','baseline','train','compare','sample','readiness-prepare','readiness-smoke','readiness-config','readiness-tests','readiness-replay','calibration-audit','calibration-tests','calibration-replay','calibration-focused','calibration-training-config','lab2a-dataset','lab2a-audit','lab2a-focused','lab2a-tests','lab2a-replay','lab2a-preflight','lab2a-prepare','lab2a-small-model']);args=parser.parse_args()
out=repo/('Evidence/ModelLab2A' if args.action.startswith('lab2a-') else 'Evidence/ModelLabCalibration' if args.action.startswith('calibration-') else 'Evidence/ModelLabReadiness' if args.action.startswith('readiness-') else 'Evidence/ModelLab1');out.mkdir(exist_ok=True)
commands={'tests':[sys.executable,'-m','unittest','discover','-s',str(root/'tests'),'-v'],'replay':[sys.executable,'-m','unittest','discover','-s',str(root/'tests'),'-v'],'tokenizer':[sys.executable,str(root/'tokenizer_preflight.py')]}
runner_args=['--model-path',str(root/'artifacts/base'),'--dataset',str(root/'data/corpus.jsonl'),'--dataset-manifest',str(root/'config/dataset-v1.json')]
commands.update({'readiness-prepare':[sys.executable,str(root/'runner.py'),*runner_args,'--mode','prepare'],'readiness-smoke':[sys.executable,str(root/'runner.py'),*runner_args,'--mode','smoke'],'readiness-config':[sys.executable,str(root/'training_preparation.py')],'readiness-tests':commands['tests'],'readiness-replay':commands['replay']})
commands.update({'calibration-audit':[sys.executable,str(root/'calibration.py')],'calibration-tests':commands['tests'],'calibration-replay':commands['replay'],'calibration-focused':[sys.executable,'-m','unittest','discover','-s',str(root/'tests'),'-p','test_calibration.py','-v'],'calibration-training-config':[sys.executable,str(root/'training_preparation.py')]})
commands.update({'lab2a-small-model':[sys.executable,str(root/'small_model_feasibility.py')],'lab2a-prepare':[sys.executable,str(root/'v2_preparation.py')],'lab2a-preflight':[sys.executable,str(root/'v2_preflight.py')],'lab2a-dataset':[sys.executable,str(root/'build_dataset_v2.py')],'lab2a-audit':[sys.executable,str(root/'semantic_v2.py')],'lab2a-focused':[sys.executable,'-m','unittest','discover','-s',str(root/'tests'),'-p','test_semantic_v2.py','-v'],'lab2a-tests':commands['tests'],'lab2a-replay':commands['replay']})
command=commands.get(args.action,[sys.executable,str(root/'lab.py'),args.action])
name='continuation-'+args.action+'-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
env={k:v for k,v in os.environ.items() if k in ['PATH','TMPDIR','LANG']};env.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',HF_HUB_DISABLE_IMPLICIT_TOKEN='1',HF_HUB_DISABLE_TELEMETRY='1',HF_HOME=str(root/'artifacts/cache'),TOKENIZERS_PARALLELISM='false')
start=datetime.datetime.now(datetime.timezone.utc).isoformat();timed_out=False;cleanup_uncertain=False
# Stream to disk so live resource samples and bounded worker logs remain inspectable.
with (out/(name+'.stdout.log')).open('w') as stdout,(out/(name+'.stderr.log')).open('w') as stderr:
    proc=subprocess.Popen(command,cwd=repo,env=env,stdout=stdout,stderr=stderr,start_new_session=True)
    try:proc.wait(timeout=180)
    except (subprocess.TimeoutExpired,KeyboardInterrupt):
        timed_out=True
        if proc.poll() is None:
            try:os.killpg(proc.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                cleanup_uncertain=True
                try:os.killpg(proc.pid,signal.SIGKILL)
                except ProcessLookupError:pass
                proc.wait(timeout=5)
        if cleanup_uncertain:
            from lab import write_json
            write_json(root/'runs/quarantine.json',{'reason':'recorder-timeout-cleanup-uncertain','commandPID':proc.pid})
    result=type('RecordedResult',(),{'returncode':2 if timed_out else proc.returncode})()
record={'action':args.action,'argv':command,'cwd':str(repo),'startedUTC':start,'finishedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exitCode':result.returncode,'recorderTimedOut':timed_out,'cleanupUncertain':cleanup_uncertain,'stdout':name+'.stdout.log','stderr':name+'.stderr.log'}
(out/(name+'.json')).write_text(json.dumps(record,indent=2));print(json.dumps(record));print((out/(name+'.stdout.log')).read_text()[-1600:]);print((out/(name+'.stderr.log')).read_text()[-1600:]);raise SystemExit(result.returncode)
