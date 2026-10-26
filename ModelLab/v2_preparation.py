"""Prepare isolated V2 training data/config metadata only; never trains or samples RAM."""
import ast,importlib.metadata
from pathlib import Path
import lab,semantic_v2 as v2

def prepare():
    cases,manifest,leakage=v2.load_frozen();lab.verify_runtime()
    defaults_source=Path(importlib.metadata.distribution('mlx-lm').locate_file('mlx_lm/lora.py'))
    tree=ast.parse(defaults_source.read_text());defaults=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='CONFIG_DEFAULTS' for t in n.targets))
    config=lab.validate_config(lab.read_json(lab.ROOT/'config/smoke.json'))
    parameters={k:v for k,v in config.items() if k in defaults}
    token_report=lab.read_json(lab.ROOT.parent/'Evidence/ModelLab2A/tokenizer-preflight.json');tokens={r['caseID']:r for r in token_report['cases']}
    if token_report['datasetFingerprint']!=manifest['corpusFingerprint']:raise lab.LabError('V2 tokenizer report changed')
    records={};directory=lab.ROOT/'artifacts/v2-prepared'
    with lab.lease():
        directory.mkdir(exist_ok=True)
        for split in ['train','valid','test']:
            selected=[c for c in cases if c['split']==split and c['status']=='COMPLETE']
            messages=[{'messages':[{'role':'system','content':lab.SYSTEM},{'role':'user','content':lab.canonical(v2.prompt(c))},{'role':'assistant','content':c['expectedResponse']}]} for c in selected]
            raw=''.join(lab.canonical(r)+'\n' for r in messages).encode();(directory/(split+'.jsonl')).write_bytes(raw)
            records[split]={'count':len(selected),'caseIDs':[r['id'] for r in selected],'sha256':lab.digest(raw),'codingCount':sum(r['expectedProposal'] is not None for r in selected),
                            'overSequenceLimit':[r['id'] for r in selected if not tokens[r['id']]['withinTraining1024']]}
        result={'state':'V2 TRAINING DATA PREPARED; TRAINING NOT READY','datasetFingerprint':manifest['corpusFingerprint'],
                'splits':records,'includedStatuses':['COMPLETE'],'excludedIDs':[c['id'] for c in cases if c['status']!='COMPLETE'],
                'configuration':parameters,'configSourceSHA256':lab.digest((lab.ROOT/'config/smoke.json').read_bytes()),
                'installedTrainerSourceSHA256':lab.digest(defaults_source.read_bytes()),'installedVersion':importlib.metadata.version('mlx-lm'),
                'modelLoaded':False,'trainingStarted':False,'hostResampled':False,
                'readinessBlockers':['No successful model baseline','No independent human/behavioral review','Only29 training coding contracts; narrow static source matching','Five incomplete original coding cases','Training memory feasibility unmeasured; no authorization to train'],
                'leakage':leakage}
        if any(r['overSequenceLimit'] for r in records.values()):result['readinessBlockers'].append('V2 prepared messages exceed unchanged1024 training sequence cap; no truncation performed')
        lab.write_json(directory/'manifest.json',result)
        lab.write_json(lab.ROOT.parent/'Evidence/ModelLab2A/training-preparation.json',result)
    print(lab.canonical({k:result[k] for k in ['state','splits','excludedIDs','modelLoaded','trainingStarted','hostResampled']}))
    return result
if __name__=='__main__':prepare()
