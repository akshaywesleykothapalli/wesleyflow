#!/usr/bin/env python3
"""Inspect installed CLI and package identities. No model loading or inference."""
import importlib.metadata, os, subprocess, sys
from pathlib import Path
from lab import ROOT, LabError, digest, write_json
if sys.prefix==sys.base_prefix:raise SystemExit('Use the dedicated ModelLab virtual environment')
env={k:v for k,v in os.environ.items() if k in ['PATH','TMPDIR','LANG']};env.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',HF_HUB_DISABLE_IMPLICIT_TOKEN='1',HF_HUB_DISABLE_TELEMETRY='1')
argv=[sys.executable,'-m','mlx_lm','lora','--help']
result=subprocess.run(argv,env=env,text=True,capture_output=True,timeout=60)
required=['--mask-prompt','--batch-size','--num-layers','--iters','--max-seq-length','--grad-checkpoint','--adapter-path','--seed']
if result.returncode!=0 or not all(x in result.stdout for x in required):raise LabError('Installed CLI inspection failed: '+result.stderr)
dist=importlib.metadata.distribution('mlx-lm');hashes={}
for file in dist.files:
    if str(file).startswith('mlx_lm/') and str(file).endswith('.py'):
        path=Path(dist.locate_file(file)).resolve();hashes[str(path)]=digest(path.read_bytes())
record={'pythonExecutable':sys.executable,'pythonVersion':sys.version,'versions':{p:importlib.metadata.version(p) for p in ['mlx','mlx-lm']},'cliArgv':argv,'cliExitCode':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'sourceHashes':hashes,'modelLoaded':False,'note':'Help/config availability only; not inference or training compatibility.'}
write_json(ROOT/'artifacts/runtime-verification.json',record)
install=ROOT/'artifacts/install-report.json'
if install.exists():
    from lab import read_json
    report=read_json(install);lines=[]
    for item in sorted(report['install'],key=lambda x:x['metadata']['name'].lower()):
        meta=item['metadata'];sha=item['download_info']['archive_info']['hashes']['sha256']
        lines.append(meta['name']+'=='+meta['version']+' --hash=sha256:'+sha)
    (ROOT/'requirements.lock').write_text('\n'.join(lines)+'\n')
record['environmentLockSHA256']=digest((ROOT/'requirements.lock').read_bytes())
write_json(ROOT/'artifacts/runtime-verification.json',record)
print('CLI exit:',result.returncode,'; version pins:',record['versions'],'; source files bound:',len(hashes),'; model loaded: false')
