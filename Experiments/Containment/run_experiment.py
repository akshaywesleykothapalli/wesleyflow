from pathlib import Path
import subprocess,datetime,json,sys,hashlib
root=Path(__file__).resolve().parents[2];e=root/'Evidence/Phase1B2A'
argv=['/usr/bin/python3',str(root/'Experiments/Containment/test_containment.py')]
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
p=subprocess.run(argv,cwd=root,capture_output=True,text=True)
data={'argv':argv,'cwd':str(root),'started_utc':started,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'harness_sha256':hashlib.sha256((root/'Experiments/Containment/test_containment.py').read_bytes()).hexdigest()}
(e/'containment-invocation.json').write_text(json.dumps(data,indent=2));print(p.stdout,p.stderr);sys.exit(p.returncode)
