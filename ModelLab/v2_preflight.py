"""Tokenizer, identity and frozen data checks only. Does not sample RAM or load weights."""
import json,os,subprocess,sys
import lab,semantic_v2 as v2
from evaluation import offline_command,offline_probe

def child():
    from transformers import AutoTokenizer
    cases,manifest,_=v2.load_frozen();tokenizer=AutoTokenizer.from_pretrained(str(lab.ROOT/'artifacts/base'),local_files_only=True,trust_remote_code=False)
    rows=[]
    for case in cases:
        messages=[{'role':'system','content':lab.SYSTEM},{'role':'user','content':lab.canonical(v2.prompt(case))}]
        prefix=lab.chat_tokens(tokenizer,messages,generation=True);full=lab.chat_tokens(tokenizer,messages+[{'role':'assistant','content':case['expectedResponse']}])
        rows.append({'caseID':case['id'],'status':case['status'],'split':case['split'],'promptTokens':len(prefix),'fullTokens':len(full),'expectedCompletionTokens':len(full)-len(prefix),
                     'withinTraining1024':len(full)<=1024,'withinInference1024':len(prefix)+320<=1024 and len(full)-len(prefix)<=320})
    chosen=next(r for r in rows if r['caseID']=='ml2a-003')
    print(lab.canonical({'cases':rows,'smokeCase':chosen,'weightsLoaded':False,'modelVersion':'1.5B cached only','datasetFingerprint':manifest['corpusFingerprint']}))

def main():
    if '--child' in sys.argv:child();return
    identity=lab.verify_model(lab.ROOT/'artifacts/base',lab.read_json(lab.ROOT/'config/model-pin.json'));lab.verify_runtime()
    proof=offline_probe();command=offline_command(lab.ROOT/'v2_preflight.py','--child')
    env={k:v for k,v in os.environ.items() if k in ['PATH','LANG','TMPDIR']};env.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_HUB_DISABLE_IMPLICIT_TOKEN='1',TOKENIZERS_PARALLELISM='false')
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=90)
    if result.returncode:raise lab.LabError('V2 tokenizer preflight failed '+result.stderr[-1000:])
    report=json.loads(result.stdout);report.update(modelIdentity=identity,command=command,exitCode=result.returncode,stderr=result.stderr,networkProof=proof)
    lab.write_json(lab.ROOT.parent/'Evidence/ModelLab2A/tokenizer-preflight.json',report)
    print(lab.canonical({'smokeCase':report['smokeCase'],'withinTraining1024':sum(r['withinTraining1024'] for r in report['cases']),'withinInference1024':sum(r['withinInference1024'] for r in report['cases']),'weightsLoaded':False}))
if __name__=='__main__':main()
