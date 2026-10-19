"""Bounded developer-only synthetic corpus run; never reconfigures or kills Ollama."""
import subprocess,os,json,time,signal
from pathlib import Path
p=Path(__file__).resolve().parents[2];e=p/'Evidence/Phase1B3A';out=e/'local-evaluation';out.mkdir(parents=True,exist_ok=True)
binary=str(p/'Packages/WesleyFlowCore/.build/debug/OllamaEvaluation')
def sample():
 result={}
 for key,argv in [('pressure',['/usr/bin/memory_pressure','-Q']),('swap',['/usr/sbin/sysctl','vm.swapusage']),('level',['/usr/sbin/sysctl','-n','kern.memorystatus_vm_pressure_level']),('vm',['/usr/bin/vm_stat']),('residency',['/usr/bin/curl','--noproxy','*','--max-time','2','--silent','--show-error','--max-filesize','131072','http://127.0.0.1:11434/api/ps'])]:
  r=subprocess.run(argv,capture_output=True,text=True);result[key]={'argv':argv,'exit_code':r.returncode,'stdout':r.stdout.strip()}
 return result
samples=[{'at':time.time(),'sample':sample()}];argv=[binary,str(out)]
start=time.time()
with (e/'local-evaluation.log').open('w') as log:
 process=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT)
 while process.poll() is None:
  if time.time()-start>1800:process.send_signal(signal.SIGINT);break
  time.sleep(0.5)
  snapshot=sample();samples.append({'at':time.time(),'sample':snapshot})
  if snapshot['level']['stdout'] not in ['1','']:
   process.send_signal(signal.SIGINT);break
 try:code=process.wait(timeout=10)
 except subprocess.TimeoutExpired:
  process.terminate();code=process.wait(timeout=10)
  # Only the owned evaluation process is stopped; daemon computation would remain uncertain.
samples.append({'at':time.time(),'sample':sample()})
(e/'local-evaluation-command.json').write_text(json.dumps({'argv':argv,'exit_code':code,'started':start,'elapsed_seconds':time.time()-start,'samples':samples},indent=2))
print((e/'local-evaluation.log').read_text());print((out/'summary.json').read_text() if (out/'summary.json').exists() else 'No completed report; inspect failure log')
raise SystemExit(code)
