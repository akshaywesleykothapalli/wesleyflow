# Replaceable local model provider

19 October 2026 · Proposal-only architecture adopted; primary future adapter Ollama. ModelProvider is a documented abstraction, not an implemented Swift protocol/target. No inference/benchmark performed in this task. Historical inventory below is not refreshed here.

## Observed inventory

Read-only local API metadata confirms Ollama client **0.33.0**, server **0.33.0**, two installed GGUF artifacts and no loaded models (`/api/ps` empty). This establishes inventory, not tool-calling quality, load footprint or speed.

| Artifact | Digest | Stored bytes | Metadata |
|---|---|---:|---|
| qwen3:8b | 500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41 | 5,225,388,164 | 8.2B, Q4_K_M, advertised context 40,960 |
| qwen2.5-coder:7b | dae161e27b0e90dd1856c8bb3209201fd6736d8eb66298e75ed87571486f4364 | 4,683,087,561 | 7.6B, Q4_K_M, advertised context 32,768 |

Read-only discovery uses `/api/tags` and `/api/ps`; model presence is distinct from residency. [Installed model API](https://docs.ollama.com/api/tags), [running model API](https://docs.ollama.com/api/ps). No model was loaded, pulled or altered.

## Provider contract

Future Domain port owns Sendable provider identity, artifact digest/license/format, capabilities, configured context/output caps, estimated peak and residency/cancellation/unload states. Methods: discover available artifacts without downloading; acquire one resource lease; generate bounded events from reviewed messages/schema; cancel exact request; unload lease; return released/uncertain with observations. All results bind request/session/generation/artifact/snapshot; provider never executes a tool call. Unknown operation kinds/fields fail proposal validation; no tool dispatcher is supplied.

ModelProviders owns Ollama HTTP transport, error mapping and resource measurement. Initially evaluate documented `/api/chat` streaming with bounded structured proposal output, with explicit context/output/keep-alive settings verified against 0.33.0 in later conformance tests. The native chat response is data only; any tool-call field is rejected by the new proposal boundary rather than dispatched. [Chat API](https://docs.ollama.com/api/chat), [tool calling](https://docs.ollama.com/capabilities/tool-calling).

The primary path is WF → ModelProvider → Ollama → bounded structured CodingProposal → Workspace validator. See [proposal contracts](PROPOSAL-CONTRACTS.md). Provider output cannot contain an executable operation or produce approval/effect/verification authority. The decoder rejects unknown commands/permission fields. No OpenCode worker or OpenCode-to-Ollama gateway is required or enabled. Historical gateway fixtures remain inert optional references, not the direct provider wire schema. Exact Ollama schema/stream/error/cancellation behavior must be verified under separately authorized1B.3 conformance tests. No endpoint permits model pulls, credentials, arbitrary destinations, configuration changes or cloud fallback.

Future MLX/user-trained artifacts implement the same consumer contract; consumers see provider capability differences, not SDK imports. Validate tokenizer/chat template, architecture/format/quantization, license, tool schema quality and reproducible hash before selection. Training/dataset work is out of scope. Failure of a required capability rejects the model; no silent vendor/cloud substitution.

## M4 / 16 GiB admission

Physical memory is 17,179,869,184 bytes (16 GiB); disk availability at inspection was about 50 GiB. A transient memory-pressure query reported 55% system free; this is neither reliable idle headroom for future work nor an admission benchmark. vm_stat showed compressed memory; free-page count alone omits reclaimable/shared allocations.

Retain provisional **8 GiB aggregate incremental** app + runtime + inference/GPU + worker/VM + verification/speech footprint, with at least **4 GiB estimated system headroom** at admission. Account guest RAM, bridge buffers, KV cache, load/prefill scratch and copy peaks. If credible measurement/headroom cannot be established, reject heavy admission. No double counting shared CPU/GPU allocations; record uncertainty and measurement method.

Start evaluation with existing 7–8B Q4 artifacts at **4,096 total context tokens**, including prompts/history/tool schemas/output reserve, and at most 1,024 output tokens. These are proposed test caps, not quality claims. Smaller 1–4B quantized artifacts may fit better but are not installed/approved for download. Raw 4-bit weight lower bounds are roughly 0.5 byte/parameter; 8B ≈4 decimal GB and 14B ≈7 GB before metadata, cache or scratch. Do not admit 14B by weight arithmetic or load both installed models. 30B+ is outside the initial evaluation.

KV bytes approximately equal `2 × layers × KV heads × head dimension × tokens × bytes per element × concurrent sequences`, subject to architecture/cache implementation. A 40k/32k advertised context is not an accepted operating point. Longer context can exhaust unified memory even when weights fit; actual configured context, quantization and runtime residency must be measured. [Ollama context guidance](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx).

One inference lease and one productive session globally. WF does not own unrelated requests on a shared Ollama daemon, so application-level serialization alone cannot guarantee global memory isolation. If foreign residency/activity or lack of reliable stop prevents accounting, reject admission; a separately owned/isolated provider deployment may be needed and requires authorization. Never kill or reconfigure the user's shared daemon.

## Load, pressure, cancellation and offline failure

Lazy load only after admission/approval. Set bounded keep-alive; request unload before memory-heavy verification, verify residency and measured release rather than trusting HTTP success. Ollama documents keep_alive=0 unloading behavior; this task did not test it. [Ollama lifecycle/FAQ](https://docs.ollama.com/faq).

Proposed inference deadline: 60 s cold readiness/first useful response and 120 s total turn, always capped by the coordinator's remaining 5 min operation/15 min family budget. No useful progress is a stall, not reason to extend. Closing the HTTP stream requests cancellation but does not establish server computation stopped. Within the shared 5 s cleanup budget, seek observable settlement/release; otherwise mark provider lease uncertain, disable new heavy work and quarantine. Shared daemon ownership limits may block this guarantee; do not fabricate an acknowledgement.

Use OS memory-pressure notifications plus recorded physical-footprint/provider residency measurements. Critical pressure stops admission immediately; sustained pressure 2 s triggers cancel/unload within 5 s or quarantine. Do not rely on swap as an acceptance strategy. Missing daemon/model, changed digest, incompatible schema, overload or unavailable offline route produces a typed failure; do not auto-start/download/retry remotely. Core shell/history/typed non-inference paths remain usable.

## Measured selection gate

Before any acceptance run, pin artifact/provider/config and freeze a 20-task disposable Swift fixture corpus (10 edit, 5 diagnostic-to-fix proposals, 5 hostile/malformed requests), seeds where supported and exact expected outcomes. Proposed pass thresholds: at least 16/20 correct bounded proposal-or-rejection outcomes, all five hostile cases produce zero forbidden dispatch, 100% emitted proposals schema-valid or explicitly rejected, and no false verified success. Report per-case outcomes rather than hiding failures behind averages. Compare both installed artifacts; select neither if neither passes.

On actual M4/16 GiB, run a fixed 30-minute cold/warm/max-configured-context/repeated load-unload/cancel/pressure workload. Record baseline/aggregate peak including any VM, swap delta, pressure/thermal state, load latency, first-response p50/p95, tokens/s, total latency, proposal field/revision accuracy and independent task outcomes. Proposed performance acceptance: p95 first useful response ≤60 s, each turn ≤120 s, aggregate ≤8 GiB, headroom ≥4 GiB at each admission, zero OOM/sustained critical-pressure episodes, and measured release or honest quarantine within 5 s. Threshold changes require a recorded decision before rerun, never retroactive relabeling. No tokens/s or quality result is claimed here.
