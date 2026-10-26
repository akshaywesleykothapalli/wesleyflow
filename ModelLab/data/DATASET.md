# Synthetic corpus v1

60 independently authored seed tasks: 48 positive Swift edits and 12 unsupported requests. Frozen splits group each task family wholly into one split. Seed 42 controls runtime randomness, not split reassignment. No private code, voice history or conversations are used.

This deliberately falls below the requested 200–500 target. Agent review and production-validator checks establish structural targets, not independent human review or executable Swift correctness. Generated source is never executed. Expand only after review, with a new corpus version; never rewrite held-out tasks to improve scores.

The actual wire discriminator is `update` (full replacement), not `replace`. The existing codec has no semantic refusal object; unsupported targets use fixed plain text that maps to malformed/proposalRejected. This preserves the current rejection boundary but cannot distinguish refusal from arbitrary malformed output at the production boundary. The evaluator counts only the exact safe refusal as correct.

Files that contain unsafe operations are adversarial validator probes, never desired training outputs.
