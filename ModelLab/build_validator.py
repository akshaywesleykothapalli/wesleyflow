#!/usr/bin/env python3
"""Recompile production Domain/Workspace with Swift 6; no package/app edits."""
import hashlib,json,os,shutil,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent;repo=root.parent;out=root/'artifacts';modules=out/'Modules';modules.mkdir(parents=True,exist_ok=True)
if shutil.disk_usage(root).free<256*1024**2:raise SystemExit('BLOCKED: insufficient disk for bridge compilation')
env=os.environ.copy();env.setdefault('DEVELOPER_DIR','/Applications/Xcode-beta.app/Contents/Developer');env.pop('SDKROOT',None)
commands=[];source_hashes={};artifact_hashes={}
def run(args):
    result=subprocess.run(args,env=env,text=True,capture_output=True);commands.append({'argv':args,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
    if result.returncode:
        (out/'validator-build.json').write_text(json.dumps({'commands':commands,'exit_code':result.returncode},indent=2));print(result.stderr);raise SystemExit(result.returncode)
    return result.stdout.strip()
toolchain={'swift':run(['/usr/bin/xcrun','swiftc','--version']),'sdk':run(['/usr/bin/xcrun','--show-sdk-version']),'sdkPath':run(['/usr/bin/xcrun','--show-sdk-path'])}
common=['/usr/bin/xcrun','swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-target','arm64-apple-macos26.0']
for module in ['Domain','Workspace']:
    sources=sorted((repo/'Packages/WesleyFlowCore/Sources'/module).glob('*.swift'))
    for path in sources:source_hashes[str(path.relative_to(repo))]=hashlib.sha256(path.read_bytes()).hexdigest()
    args=common+['-parse-as-library','-emit-module','-emit-library','-module-name',module,'-emit-module-path',str(modules/(module+'.swiftmodule')),'-o',str(modules/('lib'+module+'.dylib')),'-Xlinker','-install_name','-Xlinker','@rpath/lib'+module+'.dylib']
    if module=='Workspace':args+=['-I',str(modules),'-L',str(modules),'-lDomain']
    run(args+[str(p) for p in sources])
source=root/'Validator/main.swift';source_hashes['ModelLab/Validator/main.swift']=hashlib.sha256(source.read_bytes()).hexdigest()
run(common+['-I',str(modules),'-L',str(modules),'-lDomain','-lWorkspace','-Xlinker','-rpath','-Xlinker','@executable_path/Modules',str(source),'-o',str(out/'validator')])
for p in modules.glob('*.dylib'):artifact_hashes[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
identity={'commands':commands,'exit_code':0,'source_hashes':source_hashes,'artifact_hashes':artifact_hashes,'binding':'Fresh strict-concurrency compilation of unchanged production sources','toolchain':toolchain,'executable_sha256':hashlib.sha256((out/'validator').read_bytes()).hexdigest()}
(out/'validator-build.json').write_text(json.dumps(identity,indent=2));print('Bridge compiled successfully; production source files:',len(source_hashes),'SDK:',toolchain['sdk'])
