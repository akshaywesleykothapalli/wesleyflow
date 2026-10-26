#!/usr/bin/env python3
"""Owned bounded ML worker. Never runs model-produced code or shell commands."""
import importlib.metadata, json, math, os, sys, time, types, gc
from pathlib import Path
from lab import ROOT, LabError, SYSTEM, artifact_manifest, bridge, canonical, chat_tokens, context, digest, jsonl, prompt, read_json, score, validate_config, verify_model, verify_runtime, verify_corpus, write_json

def main():
    worker_start=time.monotonic()
    request_path=Path(sys.argv[1]).resolve()
    if request_path.parent.parent!=ROOT/'runs':raise LabError('unowned request directory')
    req=read_json(request_path);run=request_path.parent
    if req['mode'] not in ['baseline','train','compare','smoke']:raise LabError('worker mode')
    if os.environ.get('HF_HUB_OFFLINE')!='1' or os.environ.get('TRANSFORMERS_OFFLINE')!='1':raise LabError('offline environment required')
    verify_runtime()
    versions={p:importlib.metadata.version(p) for p in ['mlx','mlx-lm']}
    if versions!={'mlx':'0.32.4','mlx-lm':'0.32.2'}:raise LabError('runtime versions changed')
    config=validate_config(req['config']);pin=read_json(ROOT/'config/model-pin.json')
    identity=verify_model(req['base'],pin)
    if identity!=req['identity']:raise LabError('model identity changed')
    dataset=read_json(ROOT/'prepared/manifest.json')
    if dataset!=req['dataset']:raise LabError('dataset identity changed')
    corpus=verify_corpus(jsonl(Path(req.get('datasetPath',ROOT/'data/corpus.jsonl'))),dataset)
    for name,item in dataset['splits'].items():
        if digest((ROOT/'prepared'/(name+'.jsonl')).read_bytes())!=item['sha256']:raise LabError('split changed')
    from transformers import AutoTokenizer
    tokenizer=AutoTokenizer.from_pretrained(req['base'],local_files_only=True,trust_remote_code=False)
    # Training data is never silently truncated to fit a smoke run.
    for split in ['train','valid','test']:
        for row in jsonl(ROOT/'prepared'/(split+'.jsonl')):
            tokens=chat_tokens(tokenizer,row['messages'])
            if len(tokens)>config['max_seq_length']:raise LabError('example exceeds token budget; curate a new dataset version, do not truncate')
    from evaluation import select_cases,input_budget,bounded_generate,memory_metrics
    cases=select_cases(corpus,req['mode']) if req['mode']!='train' else []
    if cases and [r['id'] for r in cases]!=req['testIDs']:raise LabError('frozen evaluation identity')
    token_inputs={r['id']:input_budget(tokenizer,r,config) for r in cases}
    write_json(run/'worker-status.json',{'phase':'tokenizerVerified','modelLoaded':False})
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler
    mx.random.seed(config['seed'])
    mx.set_cache_limit(128*1024**2)
    # Per-process allocator cap, never a global OS/sysctl change or reserve reduction.
    mx.set_memory_limit(pin['weightBytes']+2*1024**3+(3*1024**3 if req['mode']=='train' else 0))
    adapter_directory=None
    if req['mode']=='compare':
        adapter_directory=Path(req['adapterDirectory'])
        if adapter_directory.parent.parent!=ROOT/'runs' or adapter_directory.is_symlink():raise LabError('unowned adapter')
        if digest((adapter_directory/'adapters.safetensors').read_bytes())!=req['adapterManifest']['adapterSHA256'] or digest((adapter_directory/'adapter_config.json').read_bytes())!=req['adapterManifest']['adapterConfigSHA256']:raise LabError('adapter changed')
    load_start=time.monotonic()
    model,tokenizer=load(req['base'],adapter_path=str(adapter_directory) if adapter_directory else None,tokenizer_config={'trust_remote_code':False},trust_remote_code=False)
    load_seconds=time.monotonic()-load_start
    write_json(run/'worker-status.json',{'phase':'modelLoaded','modelLoaded':True,'loadSeconds':load_seconds})
    if req['mode']=='train':
        from mlx_lm.lora import CONFIG_DEFAULTS, train_model
        from mlx_lm.tuner.datasets import load_dataset
        from mlx_lm.tuner.trainer import TrainingCallback
        losses=[]
        class FiniteCallback(TrainingCallback):
            def on_train_loss_report(self,info):
                value=float(info['train_loss'])
                if not math.isfinite(value):raise LabError('nonfinite training loss')
                losses.append(value)
            def on_val_loss_report(self,info):
                if not math.isfinite(float(info['val_loss'])):raise LabError('nonfinite validation loss')
        args=dict(CONFIG_DEFAULTS);args.update({k:v for k,v in config.items() if k in CONFIG_DEFAULTS})
        args.update(model=req['base'],data=str(ROOT/'prepared'),adapter_path=str(run/'adapter'),train=True,test=False,trust_remote_code=False,report_to=None)
        args=types.SimpleNamespace(**args)
        train_set,valid_set,_=load_dataset(args,tokenizer)
        # Direct official training entry preserves our finite-loss callback; CLI run()
        # constructs its own reporting callback in this pinned source version.
        train_model(args,model,train_set,valid_set,training_callback=FiniteCallback())
        adapter=run/'adapter/adapters.safetensors'
        if len(losses)!=config['iters']:raise LabError('smoke did not complete all finite-loss steps')
        manifest=artifact_manifest(adapter,identity,config,dataset,{'losses':losses,'steps':len(losses)})
        manifest['adapterConfigSHA256']=digest((adapter.parent/'adapter_config.json').read_bytes());manifest['environment']['packages']=versions;manifest['environment']['lockSHA256']=digest((ROOT/'requirements.lock').read_bytes());write_json(run/'adapter-manifest.json',manifest)
        write_json(run/'result.json',{'state':'TRAINING VERIFIED','adapterProduced':True,'manifest':manifest,'postTrainingEvaluation':'NOT TESTED; separate admitted adapter comparison required'})
    else:
        results=[]
        for row in cases:
            tokens=token_inputs[row['id']]
            stream=stream_generate(model,tokenizer,prompt=tokens,max_tokens=config['max_output_tokens'],sampler=make_sampler(temp=config['temperature']))
            text,metrics=bounded_generate(stream,config,memory=lambda:memory_metrics(mx))
            out=bridge([context(row,text)])[0];scored=score(row,text,out)
            from calibration import metrics
            scored["calibratedMetrics"]=metrics(row,text,out)
            scored.update(metrics);scored['loadSeconds']=load_seconds;scored['promptTokens']=len(tokens);scored['peakMLXBytes']=mx.get_peak_memory();scored['responseSHA256']=digest(text.encode());results.append(scored)
            write_json(run/(row['id']+'-response.json'),{'text':text,'syntheticOnly':True,'validation':out,'metrics':metrics})
            write_json(run/'worker-status.json',{'phase':'generated','modelLoaded':True,'casesCompleted':len(results)})
        del model,tokenizer
        gc.collect();mx.synchronize();mx.clear_cache()
        cleanup={'referencesDropped':True,'mlxAfterCleanup':memory_metrics(mx),'note':'Parent verifies process exit; these samples are not an OS-wide release guarantee.'}
        write_json(run/'result.json',{'state':'SMOKE INFERENCE VERIFIED' if req['mode']=='smoke' else 'ADAPTER INFERENCE VERIFIED' if req['mode']=='compare' else 'BASELINE INFERENCE VERIFIED','baseIdentity':identity,'evaluationFingerprint':dataset['evaluationFingerprint'],'settingsFingerprint':digest(config),'environmentFingerprint':digest((ROOT/'requirements.lock').read_bytes()),'casesRun':len(results),'coverage':{'selectedCases':len(cases),'heldOutTotal':sum(r['split']=='test' for r in corpus)},'accuracyDefinition':'legacy exact-reference rate, not semantic coding correctness','semanticCodingAccuracy':None,'accuracy':None if req['mode']=='smoke' else sum(r['exactTaskCorrect'] for r in results)/len(results),'scores':results,'adapterProduced':False,'environment':versions,'workerSeconds':time.monotonic()-worker_start,'workerCleanup':cleanup})
if __name__=='__main__':
    try:main()
    except Exception as e:
        failure={'state':'BLOCKED','error':type(e).__name__,'reason':str(e)}
        request=Path(sys.argv[1]).resolve()
        if request.parent.parent==ROOT/'runs':write_json(request.parent/'failure.json',failure)
        print(canonical(failure));sys.exit(2)
