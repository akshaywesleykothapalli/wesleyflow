from pathlib import Path
import os,sys,json
root=Path(__file__).resolve().parent;sys.path.insert(0,str(root));import lab
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',HF_HUB_DISABLE_IMPLICIT_TOKEN='1',HF_HUB_DISABLE_TELEMETRY='1',TOKENIZERS_PARALLELISM='false')
from transformers import AutoTokenizer
pin=lab.read_json(root/'config/model-pin.json');lab.verify_model(root/'artifacts/base',pin);lab.verify_runtime()
rows=lab.jsonl(root/'data/corpus.jsonl');prepared=lab.prepare(rows);config=lab.validate_config(lab.read_json(root/'config/smoke.json'))
tokenizer=AutoTokenizer.from_pretrained(str(root/'artifacts/base'),local_files_only=True,trust_remote_code=False)
results=[]
for row in rows:
 messages=[{'role':'system','content':lab.SYSTEM},{'role':'user','content':lab.canonical(lab.prompt(row))}]
 prefix=lab.chat_tokens(tokenizer,messages,generation=True)
 full=lab.chat_tokens(tokenizer,messages+[{'role':'assistant','content':row['expectedResponse']}])
 results.append({'caseID':row['id'],'split':row['split'],'promptTokens':len(prefix),'fullExampleTokens':len(full),'expectedCompletionTokens':len(full)-len(prefix),'withinSequenceCap':len(full)<=config['max_seq_length'],'generationBudgetFitsContext':len(prefix)+config['max_output_tokens']<=config['max_seq_length'],'expectedCompletionFitsOutputCap':len(full)-len(prefix)<=config['max_output_tokens']})
report={'state':'TOKENIZER PREFLIGHT VERIFIED' if all(x['withinSequenceCap'] and x['generationBudgetFitsContext'] and x['expectedCompletionFitsOutputCap'] for x in results) else 'BLOCKED','offline':True,'weightsLoaded':False,'modelRevision':pin['revision'],'corpusFingerprint':prepared['corpusFingerprint'],'evaluationFingerprint':prepared['evaluationFingerprint'],'maxExampleTokens':max(x['fullExampleTokens'] for x in results),'maxPromptTokens':max(x['promptTokens'] for x in results),'maxExpectedCompletionTokens':max(x['expectedCompletionTokens'] for x in results),'cases':results}
lab.write_json(root/'artifacts/tokenizer-preflight.json',report);lab.write_json(root.parent/'Evidence/ModelLab1/tokenizer-preflight.json',report)
print(json.dumps({k:v for k,v in report.items() if k!='cases'},indent=2))
