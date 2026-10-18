# Security and permissions strategy

## Trust boundaries and human authority

User instruction, macOS consent and model-generated proposals are distinct. Only trusted user interaction with the app's approval surface can authorize an operation. macOS microphone, Automation or Accessibility consent is capability access, not task approval. Model output, transcript text, repository files/README instructions, websites, downloaded documents, links, tool output and workflow definitions are untrusted data. They cannot change policy, raise limits, mint grants or claim that approval was given. Website content is never an instruction source; no website-fetching/browser automation feature is authorized by this packet. If introduced later, its content stays untrusted and network actions require their own policy.

App composition wires the trusted approval surface to the broker's private grant issuer. Runtime/model/voice ports expose proposals only, never that issuer. Approval UI displays plain escaped data (no active HTML/commands), distinguishes provenance, and shows exact paths, executable/argv, working directory, relevant revision/digests, changes, network scope, verification and known unrestricted effects. Only affirmative trusted user interaction mints a one-use grant bound to task, operation, app session, type, scope, digest and expiry. Default expiry is 5 minutes. Broker atomically consumes it immediately before dispatch after rechecking state, generation, scope and policy. Changed inputs, expiry, revocation, restart or duplicate dispatch invalidate it; require fresh approval. Grant values are not prompt/context content or durable restored authority.

## Human approval matrix

| Operation | Required authority |
|---|---|
| Start capture | Explicit capture gesture plus microphone consent; no execution authority |
| Submit transcript/typed task | Explicit review/submit gesture; planning only |
| Read/context discovery | Explicit selected root and bounded read/context operation approval; excludes secrets/ignored files; no write/process permission |
| Edit/create files | Exact reviewed patch/digest, destination roots and original hashes; stale hashes require reapproval |
| Delete/overwrite destructive changes | Explicit destructive confirmation naming affected resources; no inferred permission from a broad task title |
| Process, build, test or shell | Separate exact execution approval and general-purpose execution gate below; read/edit approval cannot authorize it |
| Accessibility, Apple Events, cross-app text insertion | Exact target/action/content approval plus applicable macOS consent; ordinary dictation does not grant insertion |
| Model/speech asset download | Explicit provisioning approval with source, size if available, integrity/license where applicable, progress/cancel; no hidden transcription upload |
| Sensitive evidence retention/export | Explicit content scope and retention/export destination approval; redact diagnostics |

No sudo or privilege escalation workflow. No default blanket autonomous grant. Multi-action approval may cover only an enumerated immutable bounded operation batch; new effects require new approval. User-selected roots/access bookmarks locate resources; they do not restore operation grants on restart.

## Filesystem and concurrency policy

SystemOperations alone dispatches broker-authorized filesystem effects. Workspace owns context/patch proposals and uses a scoped mediated read port. Reject traversal, outside-root symlinks, root alias bypass and reserved app/credential locations. Reserved includes application bundle/data, Keychains, SSH/cloud credentials and system files; extending access needs a separate policy decision, never project text. Use root-relative handles/no-follow operations where supported; revalidate before effect, compare original hashes and preserve user edits. Canonicalization reduces mistakes but does not solve TOCTOU races or contain arbitrary code. Reject unsupported filesystem semantics until tested.

One executing task and one productive operation at a time; workspace leases cover resolved/nested roots and aliases. The lease protects only this app's dispatch. Detect external changes using revision/hash checks, refuse stale edits, mark verification stale if relevant files change. Stage/replace per file and retain partial-effect digests as specified in [recovery order](architecture/ARCHITECTURE.md#file-modification-and-recovery-order). Never reset repositories or roll back unrelated edits.

## General-purpose execution gate

**Disabled until a separate execution ADR and explicit user authorization.** Non-sandboxed operation is accepted only for the minimal shell and deliberately bounded broker operations. An argv/root allowlist, process group, confirmation dialog, signing or Hardened Runtime does not restrict arbitrary code's filesystem, network, Keychain or descendant access. XPC separates processes/privileges but is not OS containment by itself. [Apple sandbox inheritance guidance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

The future ADR must choose one mode, document its threat model, and pass GE in TESTING:

- OS-enforced isolation with explicit filesystem/network policy and adversarial evidence of enforcement; or
- Explicitly approved unrestricted execution for user-trusted projects, with clear disclosure of user-account authority and no containment claim.

Untrusted autonomous execution stays disabled unless isolation is demonstrated. The unrestricted mode cannot enable it. There is no default choice in this packet. This open decision blocks enabling general-purpose processes/builds/tests/runtime-native execution in phases 4–6, not the separately authorized minimal 0B shell.

Each proposed process operation specifies resolved executable identity/hash or signing identity, exact argv, working directory, minimal environment allowlist, inherited descriptors, stdin scope, network policy, output cap, timeout, workspace revision and relevant file digests. Default environment excludes secrets; descriptors are closed except declared stdio; no implicit shell interpreter or model-built shell string. Scripts/build configuration can alter effects without changing argv. Any relevant mismatch requires reapproval. In unrestricted mode network/filesystem restrictions are disclosures/policy expectations, not enforceable guarantees. Do not label the mode offline merely because the model is local.

Broker owns child/process-group identity, stdout/stderr readers, 1 MiB combined capture cap, 2-second graceful and 3-second escalation deadlines and survivor reporting. Detached descendants remain a residual risk outside verified isolation. A runtime directly editing/spawning outside the broker remains unsupported until a new design explicitly accounts for that authority. See ARCHITECTURE for quarantine and quit behavior.

## macOS permissions and offline provisioning

| Capability | Policy |
|---|---|
| Microphone | First explicit capture only; usage description; denial/cancel stops capture |
| Speech | API-specific authorization, per-device/locale supported and installed checks; fail locally when unavailable; fallback order in ARCHITECTURE |
| Speech assets | Online provisioning is distinct from offline recognition; show missing/downloading/ready/failed/revoked states and cancellation; no silent cloud transcription |
| Accessibility | Approved control feature only; explain System Settings and recheck current consent |
| Apple Events | Target-specific Automation consent, usage description and actual required entitlement only |
| Project roots | Explicit selection; handle stale/revoked access; security-scoped bookmarks only where applicable; grants remain task/session-specific |
| Screen recording / Full Disk Access | Not baseline requirements; no speculative requests |
| Network | No inference/transcription upload; explicit model/speech provisioning only in baseline; general-purpose child network behavior depends on the separately selected execution mode |

Phase 0B requests no microphone, speech, Accessibility or Automation permissions. Future features add only required entitlements and validate consent with signed builds. Direct-distribution release requires Hardened Runtime, Developer ID signing and notarization evidence; Mac App Store is deferred. Neither signature nor notarization proves containment.

## Data handling and failure

Local-only Application Support store, no CloudKit sync; ordinary per-user protections, no app-encryption claim. Disk encryption depends on host configuration. Keychain is for future credentials. No raw audio retention; transcripts/prompts/argv/source/patches/tool output stay transient unless separately opted into scoped evidence retention. Context excludes credentials, ignored files and large/binary files unless a separate allowed selection is approved; reserved credentials remain denied by baseline policy. Local-first data is not silently sent remotely.

ARCHITECTURE governs schema v1, explicit commits, per-file intent/outcome, 30-day/100 MiB limits, 10 MiB recovery reserve, quota blocking, migrations and deletion. Sanitized intent/outcome/audit metadata remains essential even when content retention is off. Export redacts tokens, environment and personal paths. Do not promise forensic or backup deletion.

Revocation and emergency cleanup never wait for a successful history write. Block new effects, revoke grants, clean up within 5 seconds and show uncommitted failure if persistence is unavailable; startup reconciles the last durable intent. Recovery never resumes privileged work, restores grants or silently recreates corrupt history. Preserve partial effects and request inspection of uncertain outcomes.
