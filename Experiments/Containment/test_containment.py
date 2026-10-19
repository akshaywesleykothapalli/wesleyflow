"""Standalone characterization; never imports into production targets. Synthetic fixtures only."""
from pathlib import Path
import os,sys,json,uuid,subprocess,selectors,socket,shutil,time,signal,fcntl,select,ctypes,hashlib
ROOT=Path('/Users/akshaywesley/Developer/WesleyFlow'); E=ROOT/'Evidence/Phase1B2A'
BUILD=Path(json.loads((E/'latest-build.json').read_text())['build'])
RUN=E/('Run-'+uuid.uuid4().hex[:12]);RUN.mkdir(); records=[];checks=[];fixtures=[]
lib=ctypes.CDLL('/usr/lib/libproc.dylib');lib.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
def pathof(pid):
 b=ctypes.create_string_buffer(4096);n=lib.proc_pidpath(pid,b,4096);return b.value.decode() if n>0 else None
def check(name,value,detail=None):
 checks.append({'name':name,'passed':bool(value),'detail':detail});assert value,(name,detail)
class Reader:
 def __init__(self,p):self.p=p;self.buf=b'';self.sel=selectors.DefaultSelector();self.sel.register(p.stdout,selectors.EVENT_READ)
 def line(self,seconds=8):
  deadline=time.monotonic()+seconds
  while b'\n' not in self.buf:
   if not self.sel.select(max(0,deadline-time.monotonic())):raise TimeoutError('bounded fixture record wait')
   data=os.read(self.p.stdout.fileno(),65536)
   if not data:raise EOFError(self.buf)
   self.buf+=data
   if len(self.buf)>262144:raise ValueError('output bound')
  line,self.buf=self.buf.split(b'\n',1);return json.loads(line)
 def close(self):self.sel.close()
def launch(profile):
 argv=[str(BUILD/(profile+'.app')/'Contents/MacOS/ContainmentProbe')]
 err=(RUN/(uuid.uuid4().hex+'.stderr')).open('wb')
 p=subprocess.Popen(argv,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,env={'PATH':'/usr/bin:/bin','LANG':'C'},start_new_session=True)
 reader=Reader(p);ready=reader.line();assert ready['pid']==p.pid
 return p,reader,ready,err,argv

def fixture(ready,mode,port,inside_unrelated=False):
 token='wf-containment-'+uuid.uuid4().hex
 outer=Path('/private/tmp')/token;inner=Path(ready['temporary'])/token
 dirs={'authorized':inner/'approved','configuration':inner/'configuration','output':inner/'output','unauthorized':outer/'unauthorized','unrelated':(inner if inside_unrelated else outer)/'unrelated'}
 for d in dirs.values():d.mkdir(parents=True,exist_ok=False);(d/'input.txt').write_text('synthetic-fixture\n')
 (dirs['configuration']/'config.txt').write_text('synthetic-fixture\n');(dirs['unauthorized']/'nested').mkdir()
 (dirs['authorized']/'escape-link').symlink_to(dirs['unauthorized'],target_is_directory=True)
 (dirs['authorized']/'escape-traversal').symlink_to(dirs['unauthorized']/'nested',target_is_directory=True)
 for key,name in [('authorized','UnapprovedProbe'),('unauthorized','OutsideProbe')]:
  target=dirs[key]/name;shutil.copyfile(BUILD/'Control.app/Contents/MacOS/ContainmentProbe',target);target.chmod(0o755)
 fixtures.extend([str(inner),str(outer)])
 return {'token':token,'mode':mode,**{k:str(v) for k,v in dirs.items()},'port':port}
def send(p,value):p.stdin.write((json.dumps(value)+'\n').encode());p.stdin.flush()
def command(p,value):p.stdin.write((value+'\n').encode());p.stdin.flush()
def childwatch(pid):
 k=select.kqueue();k.control([select.kevent(pid,filter=select.KQ_FILTER_PROC,flags=select.KQ_EV_ADD|select.KQ_EV_ONESHOT,fflags=select.KQ_NOTE_EXIT)],0,0);return k
def killowned(pid,expected,k):
 if k.control(None,1,0):return True
 if pathof(pid)!=expected:raise RuntimeError('owned identity mismatch; refusing signal')
 os.kill(pid,signal.SIGKILL);return bool(k.control(None,1,3))
def unlocked(path):
 fd=os.open(path,os.O_RDWR)
 try:
  try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);return True
  except BlockingIOError:return False
 finally:os.close(fd)
def boundary(profile,index,inside=False):
 listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(16);listener.setblocking(False)
 p,r,ready,err,argv=launch(profile);rows=[];request=None
 try:
  request=fixture(ready,'probe',listener.getsockname()[1],inside);send(p,request)
  while True:
   row=r.line();rows.append(row)
   if row['type']=='probeResult':break
  p.stdin.close();code=p.wait(timeout=3);check(profile+' normal exit',code==0,code)
  received=[]
  while True:
   try:
    conn,_=listener.accept();conn.settimeout(1)
    with conn:received.append(conn.recv(256).decode())
   except BlockingIOError:break
  main=rows[-1];a={x['operation']:x for x in main['attempts']}
  for op in ['approvedRead','approvedWrite','configurationRead','outputWrite']:check(profile+' '+op,a[op]['result']>=0,a[op])
  deny=profile!='Control'
  for op in ['unauthorizedRead','unauthorizedWrite','symlinkEscape','traversalEscape']:
   check(profile+' '+op,(a[op]['result']==-1 and a[op]['error'] in [1,13]) if deny else a[op]['result']>=0,a[op])
  check(profile+' unrelated',a['unrelatedRead']['result']>=0 if inside or not deny else a['unrelatedRead']['result']==-1,a['unrelatedRead'])
  check(profile+' local network',(a['loopbackConnect']['result']==-1 and not received) if profile=='Sandbox' else a['loopbackConnect']['result']==0 and bool(received),a['loopbackConnect'])
  system=next(x for x in rows if x['type']=='systemExecutable')
  check(profile+' system executable permitted (no allowlist)',system['launched'] and system['exitStatus']==0,system)
  for name in ['unapprovedInside','unapprovedOutside']:
   item=next(x for x in rows if x['type']==name)
   check(profile+' '+name+' disposition',item['launched'] and item['exitStatus']==0 if profile=='Control' else not item['launched'],item)
  inherited=next(x for x in rows if x['type']=='inheritingChild')
  check(profile+' inherited disposition',inherited['launched'] and (inherited['exitStatus']==5 if profile=='Control' else inherited['exitStatus']==0),inherited)
  childrows=[json.loads(x) for x in inherited['output'].splitlines()];ca={x['operation']:x for x in childrows[-1]['attempts']} if childrows else {}
  for op in (['unauthorizedRead','unauthorizedWrite','symlinkEscape','traversalEscape','loopbackConnect'] if profile!='Control' else []):
   check(profile+' child '+op,ca[op]['result']==-1 if profile=='Sandbox' or (deny and op!='loopbackConnect') else ca[op]['result']>=0,ca[op])
  records.append({'kind':'boundary','profile':profile,'iteration':index,'same_container_unrelated':inside,'argv':argv,'ready':ready,'request':request,'records':rows,'exit_code':code,'listener_payloads':received})
 finally:
  if p.poll() is None:p.kill();p.wait(timeout=3)
  r.close();err.close();listener.close()

def lifecycle(mode):
 p,r,ready,err,argv=launch('Sandbox');pid=None;k=None;expected=None;rows=[];start=time.monotonic()
 try:
  request=fixture(ready,'lifecycle',0);send(p,request)
  childready=r.line();rows.append(childready);pid=childready['pid'];expected=pathof(pid);k=childwatch(pid)
  check(mode+' owned child identity',expected==str(BUILD/'Sandbox.app/Contents/Helpers/InheritedProbe'),expected)
  rows.extend([r.line(),r.line()]);childready,held,parent=rows
  check(mode+' parent child correlation',pid==int(parent['childPID']))
  lock=Path(request['authorized'])/'resource.lock'
  check(mode+' confirmed lock',held['lockResult']=='0' and not unlocked(lock),held)
  survived=None
  if mode=='forced-parent':
   p.kill();code=p.wait(timeout=3);survived=not bool(k.control(None,1,0)) and not unlocked(lock)
   check('forced parent child survives (limitation)',survived,{'parent_exit':code,'child_path':pathof(pid)})
   check('forced parent fixture cleanup',killowned(pid,expected,k));pid=None
  else:
   if mode=='timeout':
    # Operational deadline, not an ordering sleep: no further output is expected from a held fixture.
    deadline=time.monotonic()+0.2;events=r.sel.select(max(0,deadline-time.monotonic()));check('timeout watchdog fired',not events)
   if mode=='forced-child':check('forced child kill observed',killowned(pid,expected,k));k.close();k=None;pid=None
   if mode=='parent-shutdown':p.stdin.close();rows.append(r.line(2))
   else:
    command(p,'cancel');rows.append(r.line(2))
    if mode=='repeated-cancel':command(p,'cancel');rows.append(r.line(2))
    command(p,'quit');rows.append(r.line(2));p.stdin.close()
   code=p.wait(timeout=3);check(mode+' parent exit',code==0,code)
   if k:check(mode+' kernel child exit notification',bool(k.control(None,1,3)))
   pid=None
   check(mode+' cleanup acknowledges stopped',all(not x.get('running',False) for x in rows if x['type'] in ['cleanup','parentShutdownCleanup']))
  check(mode+' lock released after observed exit',unlocked(lock))
  records.append({'kind':'lifecycle','mode':mode,'argv':argv,'ready':ready,'request':request,'records':rows,'parent_exit_code':code,'child_survived_parent':survived,'elapsed_seconds':time.monotonic()-start,'resource_lock_released':True})
 finally:
  if p.poll() is None:p.kill();p.wait(timeout=3)
  if pid and k:killowned(pid,expected,k)
  if k:k.close()
  r.close();err.close()

failure=None
try:
 for i in range(3):
  for profile in ['Control','Sandbox','NetworkClient']:boundary(profile,i)
 boundary('Sandbox',3,True)
 for mode in ['cancel','timeout','repeated-cancel','parent-shutdown','forced-child','forced-parent']:lifecycle(mode)
except BaseException as ex:failure=repr(ex)
finally:
 cleanup=[]
 for root in fixtures:
  path=Path(root)
  if not path.name.startswith('wf-containment-') or path.is_symlink():raise RuntimeError('fixture cleanup scope')
  shutil.rmtree(path);cleanup.append(root)
 result={'fixture_cleanup':cleanup,'argv':sys.argv,'build':str(BUILD),'records':records,'checks':checks,'failure':failure,'passed_checks':sum(x['passed'] for x in checks),'failed_checks':sum(not x['passed'] for x in checks),'fixtures':fixtures,'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'note':'Characterization checks are not security-gate passes. Forced-parent survival and unapproved execution are security limitations.'}
 (RUN/'results.json').write_text(json.dumps(result,indent=2));(E/'latest-run.json').write_text(json.dumps({'run':str(RUN),'failure':failure,'checks':len(checks)},indent=2));print(json.dumps({'run':str(RUN),'failure':failure,'checks':len(checks),'records':len(records)}),flush=True)
if failure:sys.exit(1)
