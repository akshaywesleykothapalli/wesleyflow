from pathlib import Path
import sys,os,json,hashlib,time,urllib.request,urllib.parse,shutil,datetime
root=Path(__file__).resolve().parent;sys.path.insert(0,str(root));import lab
pin=lab.read_json(root/'config/model-pin.json')
assert pin['repository']=='mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit' and pin['revision']=='b3252a2f97102b1fb1571fec2c9b27219a8536be' and pin['totalDownloadBytes']==880172100
assert pin.get('acquisitionApproved') is True,'Separate explicit approval for this pinned acquisition is required'
assert not (root/'artifacts/base').exists(),'Existing model must be reviewed, not overwritten'
assert shutil.disk_usage(root).free >= lab.DISK_RESERVE+pin['totalDownloadBytes']
staging=root/'artifacts/base-incoming';assert not staging.exists();staging.mkdir()
class RestrictedRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  parsed=urllib.parse.urlparse(newurl)
  if parsed.scheme!='https' or not (parsed.hostname=='huggingface.co' or (parsed.hostname or '').endswith('.hf.co') or (parsed.hostname or '').endswith('.huggingface.co')):raise lab.LabError('Unapproved artifact redirect host')
  return super().redirect_request(req,fp,code,msg,headers,newurl)
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),RestrictedRedirect())
started=time.monotonic();records=[]
for item in pin['files']:
 name=item['path'];assert Path(name).name==name and name not in {'.','..'}
 url='https://huggingface.co/'+pin['repository']+'/resolve/'+pin['revision']+'/'+urllib.parse.quote(name)
 target=staging/name;sha256=hashlib.sha256();blob=hashlib.sha1(b'blob '+str(item['size']).encode()+b'\0');count=0
 with opener.open(urllib.request.Request(url,headers={'User-Agent':'WesleyFlow-ModelLab1-pinned-acquisition'}),timeout=60) as response,target.open('xb') as out:
  if response.status!=200:raise lab.LabError('Artifact HTTP status')
  while block:=response.read(1024*1024):
   if time.monotonic()-started>600:raise lab.LabError('Acquisition deadline')
   count+=len(block)
   if count>item['size']:raise lab.LabError('Artifact exceeds pinned size')
   if shutil.disk_usage(root).free<lab.DISK_RESERVE:raise lab.LabError('Disk reserve reached')
   out.write(block);sha256.update(block);blob.update(block)
 if count!=item['size'] or (sha256.hexdigest()!=item['sha256'] if item.get('sha256') else blob.hexdigest()!=item['gitBlob']):raise lab.LabError('Pinned artifact identity mismatch')
 records.append({'path':name,'bytes':count,'sha256':sha256.hexdigest(),'gitBlob':blob.hexdigest() if not item.get('sha256') else None,'source':url})
 print('Verified',name,count,'bytes',flush=True)
identity=lab.verify_model(staging,pin);staging.rename(root/'artifacts/base')
record={'completedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'repository':pin['repository'],'revision':pin['revision'],'totalBytes':sum(x['bytes'] for x in records),'files':records,'license':pin['license'],'inferenceStarted':False,'approval':'User go-ahead after the presented pinned 0.82 GiB acquisition proposal; native Codex execution approval also requested','runtimeOfflineAfterAcquisition':True}
lab.write_json(root/'artifacts/acquisition.json',record)
evidence=root.parent/'Evidence/ModelLab1';lab.write_json(evidence/'acquisition.json',record)
print('ACQUISITION VERIFIED',record['totalBytes'],'bytes; no model loaded',flush=True)
