#!/usr/bin/env python3
"""Explicit local model and frozen dataset evaluation. Smoke emits one held-out response."""
import argparse,json,sys
from pathlib import Path
import lab
from evaluation import local_path,model_metadata,versioned_dataset,prepared_matches,offline_probe

def run(model_path,dataset_path,manifest_path,mode):
    if mode not in ['prepare','smoke','evaluate']:raise lab.LabError('unsupported evaluation mode')
    model=local_path(model_path,'model');data=local_path(dataset_path,'dataset');lock=local_path(manifest_path,'manifest')
    pin=lab.read_json(lab.ROOT/'config/model-pin.json');metadata=model_metadata(model,pin);runtime=lab.verify_runtime()
    rows,manifest,quality=versioned_dataset(data,lock)
    config=lab.validate_config(lab.read_json(lab.ROOT/'config/smoke.json'))
    if mode=='prepare':
        prepared=lab.prepare(rows);prepared_matches(prepared,manifest)
        result={'state':'PREPARATION VERIFIED','model':metadata,'dataset':quality,'networkProof':offline_probe(),'inferenceAdmission':lab.admission(lab.sample(),pin['weightBytes']),'trainingAdmission':lab.admission(lab.sample(),pin['weightBytes'],True),'modelLoaded':False,'trainingStarted':False,'nextMode':'smoke'}
    else:
        if (lab.ROOT/'runs/quarantine.json').exists():raise lab.LabError('prior cleanup quarantined; review required')
        result=lab.heavy('smoke' if mode=='smoke' else 'baseline',rows,pin,config,model_path=model,dataset_path=data,dataset_manifest=manifest)
    lab.write_json(lab.ROOT/'runs'/('readiness-'+mode+'.json'),result)
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--model-path',required=True);p.add_argument('--dataset',required=True);p.add_argument('--dataset-manifest',required=True);p.add_argument('--mode',choices=['prepare','smoke','evaluate'],default='prepare');a=p.parse_args()
    result=run(a.model_path,a.dataset,a.dataset_manifest,a.mode);print(json.dumps(result,indent=2,allow_nan=False))
    return 2 if result.get('state')=='BLOCKED' else 0
if __name__=='__main__':
    try:sys.exit(main())
    except (lab.LabError,ValueError,TypeError,KeyError,OSError) as e:print(lab.canonical({'state':'BLOCKED','reason':str(e)}));sys.exit(2)
