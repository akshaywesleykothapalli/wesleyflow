"""Research-only revisions of five incomplete contracts. No inference or code execution.

Frozen V1/V2 remain authoritative for their own benchmarks. V3 supplements are
not training eligible until independent behavioral and human review exists.
"""
import copy
import json
import uuid
from pathlib import Path
import lab
import semantic_v2

SPECS = {
    "ml2a-001": ("Bounded invoice arithmetic", "Both Int operands lie in -1_000_000...1_000_000. Return their exact mathematical sum. Int is 64-bit on the target. No wrapping or saturation. Out-of-domain input is excluded from this benchmark, not silently assigned behavior.", {"maximumAbsoluteResult": 2_000_000}),
    "ml2a-009": ("Bounded chart samples", "At most 1,024 Int elements, each in -1_000_000...1_000_000. Return exact squares in input order; empty array returns empty. Maximum result is 1_000_000_000_000, representable in signed 64-bit Int. Out-of-domain inputs excluded.", {"maximumAbsoluteResult": 1_000_000_000_000, "maximumElements": 1024}),
    "ml2a-026": ("Pagination display", "Position is an Int in 0...999_999. Return the base-10, one-based display value with no grouping, spaces or leading zeros. Negative and larger positions are outside the supported domain. Maximum incremented value is 1_000_000.", {"maximumAbsoluteResult": 1_000_000}),
    "ml2a-040": ("Bounded inventory line totals", "Arrays have equal length, at most 1,024 elements each; every element lies in -1_000_000...1_000_000. Return pairwise exact products in original order. Empty inputs return empty. Unequal lengths and larger values are outside the supported domain. No wrapping or truncation policy is inferred for unsupported inputs.", {"maximumAbsoluteResult": 1_000_000_000_000, "maximumElements": 1024}),
    "ml2a-047": ("Local text counters", "At most 1,024 strings, aggregate UTF-8 payload at most 1,048,576 bytes. Sum native Swift Character counts (extended grapheme clusters), not byte/scalar counts. Empty collection returns zero. Thus the total is no larger than 1,048,576 and cannot overflow signed 64-bit Int. Larger inputs are outside the benchmark; do not claim global Unicode segmentation is validated by static matching.", {"maximumAbsoluteResult": 1_048_576, "maximumElements": 1024, "maximumUTF8Bytes": 1_048_576}),
}

def build():
    cases, manifest, _ = semantic_v2.load_frozen()
    revisions = []
    for source in cases:
        if source["id"] not in SPECS:
            continue
        title, domain, bounds = SPECS[source["id"]]
        project = str(uuid.uuid5(uuid.NAMESPACE_URL, "WesleyFlow-M30-project-" + source["id"]))
        proposal = str(uuid.uuid5(uuid.NAMESPACE_URL, "WesleyFlow-M30-proposal-" + source["id"]))
        target = source["targetRelativePath"]
        tree = [
            {"relativePath": "README.md", "content": "# " + title + "\nOffline synthetic Swift library. Only the named target is editable.\n"},
            {"relativePath": "Docs/INPUT-DOMAIN.md", "content": domain + "\n"},
            {"relativePath": "Sources/LibraryInfo.swift", "content": "// Synthetic supporting context. Not an editable target.\n"},
            {"relativePath": target, "content": None if source["supportedOperation"] == "create" else "// Synthetic implementation intentionally omitted. Replace this file only.\n"},
        ]
        context = dict(projectID=project, proposalID=proposal, entries=tree, editableTargets=[target])
        native = lab.bridge([context])[0]
        expected = copy.deepcopy(source["expectedProposal"])
        expected.update(projectID=project, proposalID=proposal, baseSnapshotDigest=native["snapshotDigest"])
        expected["changes"][0]["expectedRevision"] = native["revisions"][target]
        checked = lab.bridge([{**context, "response": lab.canonical(expected)}])[0]
        if not checked["accepted"]:
            raise lab.LabError("research reference rejected")
        revisions.append(dict(
            datasetVersion=3, id=source["id"].replace("ml2a-", "m30-"), sourceV2ID=source["id"],
            sourceV2SHA256=lab.digest(source), family=source["family"], split=source["split"],
            status="SPECIFIED_PENDING_INDEPENDENT_REVIEW", trainingEligible=False,
            instruction="Implement only " + source["behaviorContract"]["api"] + ". " + domain + " Preserve all other files. Return one full-file proposal, never apply it.",
            inputDomain=domain, arithmeticBounds=bounds, projectID=project, proposalID=proposal,
            projectTree=tree, editableTargets=[target], targetRelativePath=target,
            supportedOperation=source["supportedOperation"], workspaceRevision=native["snapshotDigest"],
            expectedFileRevision=native["revisions"][target], expectedContent=source["expectedContent"],
            expectedProposal=expected, expectedResponse=lab.canonical(expected),
            acceptableVariants="Original V2 approved source with LF/CRLF only; other algorithms unreviewed, not necessarily wrong",
            rejectionConditions=source["rejectionConditions"],
            independentValidation=dict(nativeStructuralValidatorAccepted=True, mathematicalBoundsChecked=True,
                referenceSwiftExecuted=False, independentHumanReviewed=False, modelGenerated=False),
            benchmarkPolicy="New explicit bounded-domain task; do not replace V2 scores, merge duplicate families, or promote to training automatically"))
    return dict(schemaVersion=3, kind="research-contract-supplement-not-training-corpus", frozenV2Fingerprint=manifest["corpusFingerprint"],
                revisions=revisions, splits={split:[c["id"] for c in revisions if c["split"] == split] for split in ("train", "valid", "test")},
                trainingStarted=False, modelLoaded=False, newIndependentTrainingExamples=0)


def verify():
    stored = lab.read_json(lab.ROOT / "data/research-contracts-v3.json")
    expected = build()
    if stored != expected:
        raise lab.LabError("research contract supplement changed or provenance invalid")
    return dict(state="RESEARCH CONTRACTS VERIFIED; INDEPENDENT SEMANTIC REVIEW PENDING", revisions=len(stored["revisions"]),
                fingerprint=lab.digest(stored), splits=stored["splits"], modelLoaded=False, trainingStarted=False,
                eligibleForTraining=0, nativeReferencesAccepted=5)


if __name__ == "__main__":
    print(json.dumps(verify(), indent=2))
