"""Offline review of already fetched public metadata. No downloads or model load."""
from pathlib import Path
import ast,importlib.metadata,json
import lab

def assess():
    record=lab.read_json(lab.ROOT/'config/model-0.5b-research-v1.json');directory=lab.ROOT/'provenance/model-lab2a'
    for item in record['sources']:
        p=directory/item['file']
        if lab.digest(p.read_bytes())!=item['sha256']:raise lab.LabError('research metadata changed')
    pinned=lab.read_json(directory/'community-pinned-api.json');config=lab.read_json(directory/'community-config.json')
    if record['revision']!=pinned['sha'] or record['config']!=config:raise lab.LabError('small model pin mismatch')
    by_path={f['path']:f for f in record['files']}
    for name,file in [('config.json','community-config.json'),('README.md','community-README.md')]:
        raw=(directory/file).read_bytes();expected=by_path[name]
        import hashlib
        if len(raw)!=expected['size'] or hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=expected['gitBlob']:raise lab.LabError('pinned Git blob mismatch')
    if sum(f['size'] for f in record['files'])!=record['totalRepositoryBytes'] or by_path['model.safetensors']['size']!=record['weightBytes']:raise lab.LabError('small model size accounting')
    if record['licenseDeclaration']!='apache-2.0' or 'Apache License' not in (directory/'upstream-LICENSE.txt').read_text():raise lab.LabError('license evidence unavailable')
    if record['acquisitionApproved'] or record['modelDownloaded']:raise lab.LabError('research must remain metadata-only')
    model_source=Path(importlib.metadata.distribution('mlx-lm').locate_file('mlx_lm/models/qwen2.py'));tree=ast.parse(model_source.read_text())
    args=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='ModelArgs')
    required=[n.target.id for n in args.body if isinstance(n,ast.AnnAssign) and n.value is None]
    if not set(required)<=set(config) or config['model_type']!='qwen2' or config['quantization']!={'bits':4,'group_size':64}:raise lab.LabError('metadata architecture incompatible')
    obs=lab.read_json(lab.ROOT.parent/'Evidence/ModelLab2A/admission.json')['sample']
    decision=lab.admission(obs,record['weightBytes'])
    result={'state':'METADATA COMPATIBLE; ACQUISITION NOT AUTHORIZED; INFERENCE BLOCKED AT RECORDED OBSERVATION',
            'repository':record['repository'],'revision':record['revision'],'weightBytes':record['weightBytes'],'totalRepositoryBytes':record['totalRepositoryBytes'],
            'publishedWeightSHA256':by_path['model.safetensors']['lfs']['sha256'],'license':'Apache-2.0 declared, upstream license captured',
            'installedQwen2SourceSHA256':lab.digest(model_source.read_bytes()),'requiredModelArgsPresent':required,
            'illustrativeBF16KV1024Bytes':2*config['num_hidden_layers']*config['num_key_value_heads']*(config['hidden_size']//config['num_attention_heads'])*1024*2,
            'admissionFromSameSingleObservation':decision,'hostResampled':False,'modelDownloaded':False,'weightsLoaded':False,
            'remainingShortfallBytes':max(0,decision['requiredAvailableBytes']-obs['availableBytes']),
            'compatibilityLimits':['Safetensors header/tensor layout not inspected','Tokenizer and EOS behavior not loaded or verified','Numerical compatibility and peaks not measured','Community conversion lineage stated by publisher, not independently proven'],
            'separateExperimentProposal':{'requiresSeparateApproval':True,'acquireOnlyPinnedArtifact':True,'downloadBytes':record['totalRepositoryBytes'],
                'diskReserveBytes':lab.DISK_RESERVE,'systemReserveBytes':lab.SYSTEM_RESERVE,'runtimeAllowanceBytes':lab.RUNTIME_ALLOWANCE,
                'singleSession':True,'smokeCase':'ml2a-003','contextTokens':1024,'outputTokens':320,'deadlineSeconds':120,
                'requirements':'Verify all downloaded hashes, exact tokenizer/budget compatibility, fresh unchanged admission immediately before one offline load; reject before loading on any failure. No training or code effects.'}}
    lab.write_json(lab.ROOT.parent/'Evidence/ModelLab2A/small-model-feasibility.json',result)
    print(lab.canonical({k:result[k] for k in ['state','revision','weightBytes','totalRepositoryBytes','remainingShortfallBytes','hostResampled','weightsLoaded']}))
    return result
if __name__=='__main__':assess()
