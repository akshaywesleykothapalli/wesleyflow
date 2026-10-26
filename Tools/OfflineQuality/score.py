#!/usr/bin/env python3
"""Summarize production-provider evidence, never substitute for its validator.

Meaning, grammar, tone and hallucination require reviewed actual outputs. They
remain unscored until reviewed; a lexical pass cannot establish those qualities.
Only synthetic input files belong in this tool. No inference or network access.
"""
import argparse
import json
from pathlib import Path


def score(dataset, records):
    cases = {case['id']: case for case in dataset['cases']}
    results = []
    seen = set()
    for record in records:
        case = cases[record['caseID']]
        key = (record['caseID'], record['tone'], record['kind'])
        if key in seen:
            raise ValueError('duplicate evaluation record')
        seen.add(key)
        if record['input'] != case['text'] or record['kind'] != case['kind']:
            raise ValueError('record does not match frozen synthetic input')
        status = record['status']
        if status not in {'rewritten', 'unchanged', 'resourceBlocked', 'modelUnavailable', 'timedOut', 'cancelled', 'invalidOutput'}:
            raise ValueError('unknown provider outcome')
        generated = record.get('actualMaskedModelOutput') is not None
        accepted = generated and status in {'rewritten', 'unchanged'}
        unchanged = 'not-applicable'
        if accepted and status == 'unchanged':
            unchanged = 'needs-review-missed-improvement' if case['needsImprovement'] else 'appropriate-unchanged'
        results.append(dict(caseID=case['id'], tone=record['tone'], status=status,
                            generated=generated, acceptedByProductionContract=accepted,
                            unchangedAssessment=unchanged,
                            wallSeconds=record['wallSeconds'],
                            meaning=None, grammar=None, conciseness=None, toneAppropriateness=None,
                            hallucination=None,
                            protectedSpanCheck='production-contract-passed' if accepted else 'not-established'))
    n = len(results)
    generated = sum(row['generated'] for row in results)
    return dict(datasetVersion=dataset['version'], attempted=n, generated=generated,
                resourceBlockedRate=sum(row['status'] == 'resourceBlocked' for row in results)/n if n else None,
                validOutputRate=sum(row['acceptedByProductionContract'] for row in results)/generated if generated else None,
                qualityReview='Unscored; review actual output against each rubric. Stylistic difference is not improvement.',
                results=results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset', type=Path)
    parser.add_argument('records', type=Path)
    args = parser.parse_args()
    print(json.dumps(score(json.loads(args.dataset.read_text()), [json.loads(line) for line in args.records.read_text().splitlines() if line]), indent=2))


if __name__ == '__main__':
    main()
