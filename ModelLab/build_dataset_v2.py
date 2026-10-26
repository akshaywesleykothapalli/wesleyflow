"""Materialize the authored V2 benchmark separately; default verifies frozen data."""
import argparse,json
import lab,semantic_v2 as v2

def build(write=False):
    original=lab.jsonl(lab.ROOT/'data/corpus.jsonl');lab.verify_corpus(original,lab.read_json(lab.ROOT/'config/dataset-v1.json'))
    cases=v2.build_cases(original)
    # Explicit interfaces must agree with the frozen reference; no code execution.
    for case in cases:
        if case['expectedContent'] is not None:
            api=v2.source_tokens(case['behaviorContract']['api']);reference=v2.source_tokens(case['expectedContent'])
            if case['expectedContent'].startswith('import Foundation\n'):reference=reference[2:]
            if reference[:len(api)]!=api:raise lab.LabError('API/reference discrepancy: '+case['id'])
    manifest=v2.manifest(cases,original);raw=''.join(lab.canonical(r)+'\n' for r in cases).encode()
    if write:
        (lab.ROOT/'data/corpus-v2.jsonl').write_bytes(raw);lab.write_json(lab.ROOT/'config/dataset-v2.json',manifest)
    elif raw!=(lab.ROOT/'data/corpus-v2.jsonl').read_bytes() or manifest!=lab.read_json(lab.ROOT/'config/dataset-v2.json'):
        raise lab.LabError('authored V2 does not reproduce frozen dataset')
    return {'state':'V2 WRITTEN' if write else 'V2 REPRODUCED','cases':len(cases),'corpusFingerprint':manifest['corpusFingerprint']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');a=p.parse_args();print(lab.canonical(build(a.write)))
