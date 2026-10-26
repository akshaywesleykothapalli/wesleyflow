"""Local-only evaluation helpers. No model imports, download helpers or effect ports."""
from pathlib import Path
import json,os,subprocess,sys,time
import lab
PROFILE='(version 1)\n(allow default)\n(deny network*)\n'

def local_path(value,kind):
    p=Path(value)
    if not p.is_absolute():raise lab.LabError('absolute local '+kind+' path required; hub IDs and URLs are unsupported')
    if any(x.is_symlink() for x in [p,*p.parents]):raise lab.LabError('symlink '+kind+' path rejected')
    try:p=p.resolve(strict=True)
    except FileNotFoundError:raise lab.LabError('missing local '+kind+': '+str(p))
    if kind=='model' and not p.is_dir():raise lab.LabError('local model directory required')
    if kind!='model' and not p.is_file():raise lab.LabError('local data file required')
    return p

def model_metadata(model,pin):
    identity=lab.verify_model(model,pin)
    c=lab.read_json(model/'config.json')
    if c.get('architectures')!=['Qwen2ForCausalLM'] or c.get('model_type')!='qwen2' or c.get('quantization')!={'group_size':64,'bits':4}:raise lab.LabError('unsupported pinned quantization/architecture')
    if c.get('max_position_embeddings',0)<1024 or c.get('num_key_value_heads')!=2 or c.get('num_hidden_layers')!=28:raise lab.LabError('pinned architecture limits changed')
    with (model/'model.safetensors').open('rb') as f:
        n=int.from_bytes(f.read(8),'little')
        if not 2<=n<=1048576:raise lab.LabError('model tensor header bounds')
        header=json.loads(f.read(n))
    if not any(k.endswith('.scales') for k in header) or not any(isinstance(v,dict) and v.get('dtype')=='U32' for v in header.values()):raise lab.LabError('quantized tensor metadata missing')
    return {'identity':identity,'architecture':c['architectures'],'quantization':c['quantization'],'tensorHeaderVerified':True,'numericalCompatibility':'NOT TESTED until a real load'}

def versioned_dataset(path,manifest_path):
    rows=lab.jsonl(path);manifest=lab.read_json(manifest_path)
    if manifest.get('schemaVersion')!=1:raise lab.LabError('unsupported dataset manifest version')
    lab.verify_corpus(rows,manifest)
    report=lab.validate_rows(rows)
    for name in ['train','valid','test']:
        selected=[r for r in rows if r['split']==name]
        if [r['id'] for r in selected]!=manifest['splits'][name]['ids'] or len(selected)!=manifest['splits'][name]['count']:raise lab.LabError('split identity mismatch')
    return rows,manifest,report

def prepared_matches(prepared,manifest):
    for name in ['corpusFingerprint','evaluationFingerprint','splitAlgorithm','splits']:
        if prepared.get(name)!=manifest.get(name):raise lab.LabError('prepared data differs from frozen manifest: '+name)

def select_cases(rows,mode):
    cases=[r for r in rows if r['split']=='test']
    if mode=='smoke':
        cases=next(([r] for r in cases if r['expectedDisposition']=='accept'),[])
    if not cases:raise lab.LabError('no eligible held-out cases')
    return cases

def offline_command(worker,request):
    sandbox=Path('/usr/bin/sandbox-exec');profile=lab.ROOT/'config/offline-worker.sb'
    if not sandbox.is_file() or profile.read_text()!=PROFILE:raise lab.LabError('verified network-denying worker sandbox unavailable')
    return [str(sandbox),'-f',str(profile),sys.executable,str(worker),str(request)]

def offline_probe():
    profile=lab.ROOT/'config/offline-worker.sb'
    command=offline_command(lab.ROOT/'network_probe.py',lab.ROOT/'config/smoke.json')
    result=subprocess.run(command,text=True,capture_output=True,timeout=10,env={'PATH':'/usr/bin:/bin','HF_HUB_OFFLINE':'1'})
    try:report=json.loads(result.stdout)
    except ValueError:raise lab.LabError('offline network-denial probe failed')
    if result.returncode!=0 or report.get('ipv4Denied') is not True or report.get('ipv6Denied') is not True:raise lab.LabError('worker network denial not established')
    return {**report,'argv':command,'exitCode':result.returncode,'profileSHA256':lab.digest(profile.read_bytes()),'scope':'network-denial for the owned research worker only; not a general filesystem/agent containment guarantee'}

def bounded_generate(stream,config,clock=time.monotonic,memory=lambda:{}):
    start=clock();first_token=None;first_text=None;parts=[];size=0;count=0;observed={}
    def observe():
        for k,v in memory().items():
            if type(v) is int and v>=0:observed[k]=max(v,observed.get(k,0))
    observe()
    try:
        for response in stream:
            now=clock()
            if now-start>=config['deadline_seconds']:raise lab.LabError('generation deadline')
            text=response.text;generated=response.generation_tokens
            if not isinstance(text,str) or type(generated) is not int or not count<=generated<=config['max_output_tokens']:raise lab.LabError('generation token/shape limit')
            count=generated
            if first_token is None:first_token=now-start
            if text and first_text is None:first_text=now-start
            size+=len(text.encode())
            if size>65536:raise lab.LabError('response-size limit')
            parts.append(text);observe()
    finally:
        close=getattr(stream,'close',None)
        if close:close()
    if first_token is None or count<=0:raise lab.LabError('no generated tokens')
    return ''.join(parts),{'timeToFirstTokenSeconds':first_token,'timeToFirstTextSeconds':first_text,'generationSeconds':clock()-start,'generatedTokens':count,'responseBytes':size,'memoryObserved':observed}

def memory_metrics(mx):
    values={}
    for key,name in [('nativePeakMLXBytes','get_peak_memory'),('observedActiveBytes','get_active_memory'),('observedCacheBytes','get_cache_memory')]:
        fn=getattr(mx,name,None)
        if callable(fn):values[key]=int(fn())
    return values

def input_budget(tokenizer,row,config):
    tokens=lab.chat_tokens(tokenizer,[{'role':'system','content':lab.SYSTEM},{'role':'user','content':lab.canonical(lab.prompt(row))}],generation=True)
    if len(tokens)+config['max_output_tokens']>config['max_seq_length']:raise lab.LabError('evaluation context budget')
    return tokens
