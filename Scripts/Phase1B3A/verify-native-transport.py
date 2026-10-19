"""Developer-only loopback fixture server. No model requests, tools or real-project reads."""
import http.server,threading,subprocess,json,sys,socket,time
from pathlib import Path
binary=sys.argv[1]; output=Path(sys.argv[2]); output.mkdir(parents=True,exist_ok=True)
records=[]
class Fixture(http.server.BaseHTTPRequestHandler):
 mode='success';requests=[]
 def log_message(self,*args):pass
 def do_GET(self):
  type(self).requests.append({'path':self.path,'authorization_present':bool(self.headers.get('Authorization'))})
  if self.mode=='drop':self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
  self.send_response(302 if self.mode=='redirect' else 200)
  self.send_header('Content-Type','application/json')
  if self.mode=='redirect':self.send_header('Location','http://nonlocal.invalid/not-authorized')
  self.end_headers()
  if self.mode=='timeout':time.sleep(0.8);return # Stall fixture tests the actual resource timeout, never orders concurrent unit tests.
  try:self.wfile.write(b'x'*1024 if self.mode=='oversize' else b'{"version":"fixture"}')
  except (BrokenPipeError,ConnectionResetError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Fixture);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
 for mode,expected in [('success','transportStatus=200'),('redirect','transportFailure=redirectDenied'),('oversize','transportFailure=oversized'),('timeout','transportFailure=timeout'),('drop','transportFailure=unavailable')]:
  Fixture.mode=mode;Fixture.requests=[];argv=[binary,'--probe-transport','http://127.0.0.1:'+str(server.server_port)]
  r=subprocess.run(argv,capture_output=True,text=True,timeout=10)
  record={'case':mode,'argv':argv,'exit_code':r.returncode,'stdout':r.stdout.strip(),'requests':list(Fixture.requests)};records.append(record)
  assert r.returncode==0 and expected in r.stdout,record
  # CFNetwork can internally retry an idempotent GET after a connection drop.
  # Other probes (especially redirect) must have exactly one observed local request.
  assert (1 <= len(Fixture.requests) <= 3 if mode=='drop' else len(Fixture.requests)==1),record
  assert all(x['path']=='/api/version' and not x['authorization_present'] for x in Fixture.requests),record
finally:
 server.shutdown();server.server_close();thread.join(timeout=2)
 (output/'native-transport-tests.json').write_text(json.dumps(records,indent=2))
print('Five native loopback HTTP transport probes passed; no redirect target followed and no credentials sent')
