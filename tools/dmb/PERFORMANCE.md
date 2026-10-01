# Compiler iteration and concurrency

## Measurements

Measured on October 1, 2026 against the frozen full-project comparison snapshot
(48,681 ordinary procedures; CBT/CIBUILDING/CITESTING). No DreamDaemon runs are
included. Prototype builds optimize the hot compiler and binary-format crates.
These are observations with warm operating-system file caches, not guarantees.

| Scenario | Wall time |
| --- | ---: |
| Daemon, one ordinary procedure body edit | 3.240 s |
| Daemon, unchanged project | 0.032 s |
| New CLI process, unchanged source and output, persisted receipt | 0.152 s |
| New CLI process, one body edit, disk caches | 11.722 s |
| Two worktrees, concurrent body edits | 3.834 s total |
| Two worktrees, concurrent unchanged builds | 0.040 s total |

The single edit lowered one procedure and reused 48,680. Preprocessing took
0.951 s, resource discovery/fingerprinting about 0.15 s, compiler/emission 0.278 s,
checkpoint publication 0.394 s, final input validation 0.347 s, and generation
publication 0.738 s. Before proof reuse and cache sizing fixes, the same body-edit
scenario took 29.032 s, including 20.187 s of final validation.

The concurrent run peaked at 1,898.6 MiB private process memory. Both worktrees
lowered their changed procedure and reused 48,680 others. Both requests execute
on independent compiler workers.

A compiler-version cache rebuild took 103.928 s, including 80.840 s compiler
work and 8.348 s initial input proof setup. It was not a fully empty cache:
2,695 lowering entries were reused. A reset-source baseline is also not an
unchanged restart; use the separate unchanged CLI measurement above.

## Unchanged builds

Successful generation builds persist a compact **build receipt** in the compiler
cache. A new CLI process can verify that receipt and return the existing output
without preprocessing the project, restoring compiler tables, or loading the
entire expanded source. The receipt contains the source fingerprint, result,
input file proofs, missing dependencies, resource search directories, and resolved
resource names and paths. It does not contain the expanded project.

Receipts and compiler artifacts are content addressed. Each receipt index is
published with a unique temporary file followed by an atomic rename. The latest
four index records are retained per project/output context. Separate processes
can publish records without overwriting each other's temporary files or violating
immutable artifact keys. Damaged, missing, or incompatible receipts cause a
normal compilation path.

When a source edit invalidates a disk receipt, its authenticated input proof can
still identify unchanged files and assets. The cached build result is rejected;
discovery rebuilds the changed closure and rechecks selected resource paths.
This preserves eligible file barriers across daemon restarts.

File proofs use more than size and modification time:

- Windows: file identity, volume identity, creation time, change time, size, and
  modification time, plus the per-file NTFS USN, obtained from an exclusive
  read handle. Unavailable USNs or conflicting reader/writer handles force
  exact input validation. The USN distinguishes rapid writes that share a
  timestamp because of filesystem clock granularity.
- Unix: device, inode, change time with nanoseconds, size, and modification time.
- Unsupported metadata APIs: exact content validation remains the fallback.

A same-size edit with its modification time restored still invalidates the proof.
Atomic file replacement invalidates the identity. Proofs are established by
capturing metadata **before** exact input validation and comparing it **after**.
This prevents adopting metadata for a file changed during validation.

On Windows, supported volumes can additionally use a persisted NTFS journal
proof. It captures journal cursors before briefly opening each watched file with
exclusive sharing. A sharing conflict disables this shortcut; no lock is retained
after establishing the proof. Successful barriers prove that an older reader or
writer cannot retain a previously accumulated journal reason flag. The first
subsequent change then invalidates the proof, including when a writer keeps its
handle open and later writes are coalesced into the same journal reason.
The final validation establishes one complete journal baseline. Asset subsets
inherit that baseline with filtered file IDs, so they do not repeat the exclusive
barrier pass. A source-only change can invalidate the complete proof while
leaving its asset subset reusable.

Warm validation scans bounded journal records and the physical identities of
unique lexical ancestor directories. Directory handles inspect reparse points
themselves and separately follow them to compare the physical target directory's
identity and volume. Moving a directory or retargeting a junction therefore
invalidates the proof even when timestamps or directory journal reasons coalesce.
Directory timestamps and child-entry changes are not proof keys: creating an
unrelated cache or log file does not invalidate source. New include candidates
and resource shadows remain explicit checks.
Directory readers such as IDE watchers can remain open; files require exclusive
sharing only while establishing the journal baseline or fallback metadata proof.
Journal deletion, ID changes, wrapping, unsupported records, sharing conflicts,
or API errors fall back to per-file metadata checks. It neither creates nor
modifies a volume journal. Unknown record formats never imply an unchanged file.

The fast validation contract covers ordinary file writes and editor replacements.
Use `DM_BUILD_EXACT_INPUTS=1` for memory-mapped or raw writes that may bypass file
metadata/journal updates; this rereads exact input contents instead. Windows does
not guarantee timestamp updates for writes through mapped views.

Every reuse checks missing include candidates and resource search resolution.
A newly created resource that shadows an existing `FILE_DIR` resource therefore
invalidates the receipt even when the original asset has not changed.

Published DMB/RSC pairs are verified independently. The output layer persists a
checksummed proof after verifying actual bytes and uses the same strong metadata
rules to accelerate subsequent verification. Corruption invalidates that proof.

## Small source edits

The compiler retains a bounded expanded input snapshot in a daemon session.
Expanded source has a 64 MiB limit; the aggregate retained snapshot budget is
96 MiB to include dependency tables and metadata proofs for near-limit projects.
Source providers capture strong stamps before reading original source bytes,
then verify those stamps after discovery and again before publication. They keep
the original stamps when replaying a previously read source. This avoids redundant
source rereads while still rejecting edits made during compilation.
Changing source requires preprocessing and discovering the new input closure.
Procedure checkpoints allow unchanged bodies to be reused.

The discovery session retains source bytes and their exact digests, reading only
files invalidated by the input proof. Its combined source/expansion budget is
224 MiB (64 MiB source and 160 MiB expansions). Preprocessing caches nested include subtrees and their macro, source-map,
map, skin and `FILE_DIR` effects. Macro keys include relevant transitive and
undefined names; dynamic directive and token-paste cases use the complete macro
environment. Disk entries are separate checksummed shards with an atomic index,
so an edit writes changed shards rather than serializing the complete cache.

The frontend retains content-addressed compact AST fragments and procedure
outlines within a 128 MiB budget. Source-relative spans allow unchanged syntax to
survive movement earlier in the expansion. Procedure source is shared through
immutable references. Source order and duplicate definitions are reconsidered
when assembling the outline, preserving override semantics. Syntax shards are
shared across worktrees and fresh processes under the project cache directory.
Resource inventories use the same safe lexical chunks, retaining ordered literal
spans and rescanning changed chunks. Oversized layouts use the complete scanner.

Each worker can retain one linked DMB/checkpoint within a separate 320 MiB budget.
A successful body patch preserves unshared code-list IDs and records changed
list IDs. The indexed serializer encodes those lists and copies unchanged spans;
it does not re-encode every list or repeatedly decode the previous linked world.
Structural changes retain the guarded full-link fallback and reuse eligible
procedure lowering artifacts by their complete dependency keys.

If resource names and resolved paths, map includes, and the existing asset proof
remain identical, the compiler reuses the resource fingerprint. Final validation
also avoids rereading unchanged assets and maps. It still scans the newly expanded
source for resource requests, checks resource shadows, and validates changed
source. Header, macro, inheritance, map, or asset changes can invalidate more work
than a procedure-body edit.

## Parallel compilation

`DM_COMPILER_WORKERS` controls bounded procedure lowering:

- `1`: serial parsing and lowering, using the same ordered batch layout.
- `2`: the default; persistent workers parse, read syntax caches and lower
  symbolic bytecode while the coordinator commits completed batches in order.

Linking remains ordered because it allocates shared bytecode table IDs. Ordinary
procedures, dynamic initializer groups and argument-source helpers use the same
bounded pool. At most two jobs are in flight, with no per-job DMB clone. Worker
lowering caches share a 48 MiB aggregate budget. Single-worker and two-worker
output is deterministic. Map file reads also overlap in ordered batches of two.

## Parallel worktrees

`DM_DAEMON_WORKERS` accepts `1` through `4`, defaulting to `2`. Each worker owns
its compiler databases and retained state. Worktrees are routed to a worker so
requests for one worktree remain ordered while different workers can compile
independent worktrees simultaneously. Request queues are bounded; overload is
reported to the client rather than accumulated without limit.

Independent CLI processes and separate daemons also share immutable disk caches.
Give each worktree its own output directory and each daemon its own port. A build
receipt is scoped to its project, compiler fingerprint, builtins, target, defines,
mode, and output directory. Procedure artifacts can still be shared across
worktrees when their complete dependency keys match.

The daemon's process memory limit applies to all its workers together. Start with
two workers; increasing concurrency also increases live compiler state. The
default Windows process budget remains 2 GiB unless explicitly overridden with
`DM_MEMORY_LIMIT_MB`.

## Binary patching

Fixed-layout patching writes changed byte spans with a recovery journal. It
requires exclusive ownership of stopped output files. Layout changes require a
new generation. Both `build-project-patch` and `build-project-patch-daemon` use
the coordinator's persisted project and procedure checkpoints. A fresh CLI
process can reuse a cached pair for unchanged inputs; a small body edit can
lower only changed procedures while retaining the other bodies. Patch reports
include the output-cache result and lowered/reused procedure counts.

The patch path still verifies the existing output pair and constructs or restores
the desired pair before comparing it. It does not use the generation-build
receipt shortcut, so unchanged patch requests can cost more than unchanged
generation builds. Patching reduces disk writes and cached lowering work, but
does not remove all linking, validation, or comparison work.

## Correctness checks

Focused tests cover preserved-modification-time edits, atomic replacement,
resource shadowing, cold receipt reuse without preprocessing, receipt corruption
fallback, output corruption, serial/parallel ordering, early producer shutdown,
bounded daemon queues, and independent worker progress. Workspace tests provide
the broader integration gate. Measurements must use the final compiler
fingerprint so caches from an older implementation cannot silently count as warm.

## Retained incremental state

Each worker retains bounded discovery and frontend caches plus one linked world
(up to 320 MiB including its serialized list index). An ordinary procedure edit
reuses decoded metadata, stable procedure/list IDs, unchanged list bytes, and the
resource archive. Changed list records may grow or shrink in a new generation;
non-list metadata changes use the complete writer. Declaration or ABI changes
retain the guarded full-assembly fallback.

On Windows, file and namespace journal proofs validate unchanged inputs in volume
batches. Dirty or new files receive new exclusive verification barriers; unchanged
files retain their prior proof. Junction ancestors also receive direct lexical and
followed identity checks because held-handle reparse edits can coalesce journal
records. Journal loss, unsupported filesystems, or ambiguous changes fall back to
strong file verification. Proof groups and retained caches are bounded.

Generation publication supports both legacy generation IDs and a versioned digest
ID. A verified immutable archive can be linked or copied while an exclusive reader
protects it, avoiding repeated archive decoding and hashing on procedure edits.
If the archive proof cannot be held, publication uses verified cached bytes.
