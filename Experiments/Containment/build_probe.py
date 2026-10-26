from pathlib import Path
import subprocess,os,json,plistlib,sys,uuid,hashlib,datetime
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'Experiments/Containment';E=ROOT/'Evidence/Phase1B2A';E.mkdir(parents=True,exist_ok=True)
runid=uuid.uuid4().hex[:12];out=E/('Build-'+runid);out.mkdir();env=os.environ.copy();env['DEVELOPER_DIR']='/Applications/Xcode-beta.app/Contents/Developer';env.pop('SDKROOT',None);results=[]
sdk=subprocess.check_output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True).strip()
def run(name,args):
 p=subprocess.run(args,cwd=ROOT,env=env,capture_output=True,text=True);(out/(name+'.log')).write_text(p.stdout+p.stderr);results.append({'name':name,'argv':args,'exit_code':p.returncode});assert p.returncode==0,p.stdout+p.stderr
for config,flags in [('Debug',['-Onone','-g']),('Release',['-O'])]:
 binary=out/('Probe-'+config)
 run('compile-'+config,['/usr/bin/xcrun','swiftc','-parse-as-library','-swift-version','6','-strict-concurrency=complete','-sdk',sdk,'-target','arm64-apple-macos26.0']+flags+[str(SRC/'ContainmentProbe.swift'),'-o',str(binary)])
for profile,ent in [('Control',{}),('Sandbox',{'com.apple.security.app-sandbox':True}),('NetworkClient',{'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True})]:
 app=out/(profile+'.app');main=app/'Contents/MacOS/ContainmentProbe';helpers=app/'Contents/Helpers';main.parent.mkdir(parents=True);helpers.mkdir()
 import shutil
 shutil.copyfile(out/'Probe-Debug',main);main.chmod(0o755)
 inherited=helpers/'InheritedProbe';shutil.copyfile(out/'Probe-Debug',inherited);inherited.chmod(0o755)
 entfile=out/(profile+'.plist');entfile.write_bytes(plistlib.dumps(ent));inheritfile=out/'inherit.plist';inheritfile.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.inherit':True}))
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.wesleyflow.containment.'+profile.lower()+'.'+runid,'CFBundleExecutable':'ContainmentProbe','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleName':'WesleyContainmentExperiment','LSUIElement':True,'LSMinimumSystemVersion':'26.0'}))
 run('sign-child-'+profile,['/usr/bin/codesign','--force','--sign','-','--identifier','local.wesleyflow.containment.child.'+runid,'--entitlements',str(inheritfile),str(inherited)])
 run('sign-main-'+profile,['/usr/bin/codesign','--force','--sign','-','--entitlements',str(entfile),str(app)])
 run('verify-'+profile,['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',str(app)])
 run('entitlements-'+profile,['/usr/bin/codesign','--display','--verbose=4','--entitlements',':-',str(app)])
 run('child-entitlements-'+profile,['/usr/bin/codesign','--display','--verbose=4','--entitlements',':-',str(inherited)])
(out/'commands.json').write_text(json.dumps(results,indent=2));(E/'latest-build.json').write_text(json.dumps({'build':str(out),'runid':runid,'source_sha256':hashlib.sha256((SRC/'ContainmentProbe.swift').read_bytes()).hexdigest(),'DEVELOPER_DIR':env['DEVELOPER_DIR'],'SDKROOT':sdk,'commands':results},indent=2));print(str(out),flush=True)
