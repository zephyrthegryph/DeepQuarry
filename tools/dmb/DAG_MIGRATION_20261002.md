# Disk-backed compiler migration checkpoint � 2026-10-02

Worktree branch: `codex/compiler-architecture`. Implementation is in progress.
No Rust tests, DM tests or DreamDaemon runs were performed in this iteration.
Cargo builds and real-project compiler benchmarks are the verification used.

## Implemented data flow

1. Source discovery retains immutable metadata and content-addressed authored files.
   Eviction drops decoded text while retaining disk handles, include context and proofs.
   Expansion pieces are individually addressed, shared and persisted; changed generations
   write only new source/expansion content. Disposable cache writes avoid per-file fsync;
   published output generations remain durable.
2. Segmented syntax produces immutable local AST fragments and source offsets. The
   native compiler consumes borrowed declaration fragments; structural skeleton misses
   materialize only their declaration projection. Procedure body text is fetched on misses.
3. Symbolic owners use persistent maps and per-owner recipe nodes. Defaults save exact
   positive and negative observations. The same observations feed shared typed Salsa
   inputs and persisted candidate validity, refreshed once per immutable model generation.
4. Procedure candidates use compact interned facts, values and reverse dependency edges.
   Requested headers/payloads load in source order. Decoded residency is independent of
   validity; output fragments replay ordered allocation recipes and typed relocations.
5. Resource inventories persist independently of source retention. Named asset entries
   are immutable files; new archives stream their active deterministic sequence through
   bounded buffers. Unchanged archives publish by verified identity and hardlink without
   payload loading. New physical entries accumulate; historical inactive entries are not
   included in generated RSC bytes.
6. Cache metadata uses redb with short cross-process ownership. Grouped requested reads
   amortize database opening while preserving per-group and aggregate memory bounds.
   No database handle is retained during semantic processing or output generation.
7. Analysis JSONL schema 2 uses shared syntax fragments and native owner/field/value
   queries. General expression-reference resolution and resolved parameter types remain
   explicitly unavailable; consumers must inspect coverage.

## Measurement evidence, before the latest fixes

All runs used the real DeepQuarry fixture, `CBT`, `CIBUILDING`, `CITESTING`, two
workers and a 3 GiB process limit. OS caches were not flushed.

- Run A was stopped after 961.9 seconds before completing a cold baseline.
- Run B failed at resource archive creation because a Windows strong-stamp check
  occurred while the source reader was open. Readers are now closed before that check.
- Run C timed out at the 600-second phase limit. It is a failed/incomplete benchmark,
  not a successful cold compilation timing. Its trace measured source preparation
  27.117 s, resource discovery 1.973 s, resource hashing 3.367 s, streamed archive
  creation 10.580 s, symbolic owner model 123.983 s, and declaration allocation
  226.970 s. It reached about 30,720 of 68,411 authored procedures before timeout.

The latest, not yet benchmarked fixes batch owner/default reads, directly consume
parallel owner plans, eliminate whole symbolic namespace scans and empty loose-file
probes, replace constant-cache linear eviction scans with an ordered recency index,
reuse lexical passes, and optimize the new persistent-map/query/storage dependencies
in development compiler executables. These changes require a new build and measurement;
no speedup or runtime correctness is claimed for them yet.

Raw failed-run receipts: `target/deepquarry-dag-iteration-20261002-{a,b,c}`.
The earlier successful timing report remains `ITERATION_TIMINGS_20261002.md`.

## Remaining acceptance work

Measure the rebuilt compiler on cold, unchanged, body, structural, resource and restart
cases; identify and remove remaining observed bottlenecks. Source fallback batching,
analysis reference coverage, and six-worktree performance acceptance are still open.
Runtime parity and deterministic replay gates remain deferred by the current instruction
not to run correctness suites. This checkpoint is not a declaration of 100% completion.

## Next checkpoint: measured run D and subsequent implementation

Run D completed cold compilation in 393.906 s, unchanged output in 0.208 s,
and one body edit in 443.275 s. Reverting the body took 26.987 s through a
cached output pair. The benchmark was stopped during the structural case;
these are individual successful measurements, not a completed benchmark.

The owner model stage fell from 123.983 s in C to 10.028 s in D. Detailed
traces exposed repeated database opens for already-derived owner frames,
flattened inherited-field inventories exceeding retention budgets, missing
initializer graph headers, and invocation syntax reads falling out of the
bounded decoded cache. Subsequent implementation removes those owner reads,
shares persistent parent maps, releases transient owner generations, restores
initializer headers before fact validation, and batches invocation reads in
source-order consumption windows. Expansion blobs are now lazy disk handles;
source journal coverage survives combination with independently checked assets.
Initial resource discovery repairs damaged expansion caches once and retries.

These subsequent changes still require a rebuilt benchmark. No Rust or DM
correctness tests were run. The overnight continuation remains active.

## Run E interim measurements

Rebuilt prototype: cold 250.837 s; unchanged 0.270 s; one procedure edit
86.147 s (68,410 authored procedures reused, one lowered; 13,921 generated
initializers reused with none lowered). The run is still in progress, so these
are interim successful cases. Cold compiler stage: 210.378 s. Edit compiler
stage: 72.347 s. Edit header restoration: 24.720 s for 82,438 headers, including
19.302 s requested disk reads. Metadata retention remains above the 512 MiB
pool budget and evicts the frontend; compact retention is the next target.
No runtime correctness tests were run.

Run E completed successfully as a compiler benchmark (not runtime tests):
new proc 179.523 s; new var 181.604 s; default edit 130.399 s;
asset edit 104.383 s; add resource 152.177 s; fresh cached process 0.235 s;
fresh process with body edit 87.479 s. All cases reported successful native
compilation. Compact certificates, compressed skeleton indexes, one-pass
unit hashing, and independent bytecode catalog caching were implemented after
this executable and remain unmeasured until the next build.

## Failed run F and following migration

Run F failed at cache publication with `invalid artifact key`; its 210.348 s
request is not a successful cold compilation measurement. The new independent
bytecode key incorrectly appended a plaintext world name to digest fields;
this now uses SHA-256. Its compiler stage completed in 172.902 s and showed
compact graph metadata at192.0MB versus278.4MB in E, still slightly over the
retention budget. Subsequent code replaces reverse-edge tree nodes with u32
pages, releases duplicate invocation caches, compresses source origins into
immutable affine runs, and uses MessagePack fragment metadata. Default plans
now run in bounded parallel owner windows, respecting configured worker limits.
The byte export API now materializes an archive when callers request bytes
instead of a generation, including after independent bytecode reuse.

No correctness tests were run. These following changes require run G.

## Run G and direct composition integration

G completed: cold212.006s, unchanged3.205s, body127.091s, newproc134.081s,
newvar121.855s, default108.396s, asset94.983s, newresource120.865s,
freshcachedprocess0.160s, freshbody72.882s. All compiler requests succeeded;
this does not establish runtime correctness. Warm regression was traced to
external encoding/shared lookup caches pushing the aggregate budget over its
limit at the next request. New request handling trims these cheap optional
indexes before evicting session dependency graphs.

The next prototype routes canonical published builds through one chunked
physical DMB encoder, immutable256KiB disk pages and ordered SHA manifests.
CAS storage and generation publication stream verified pages; the full byte
buffer remains an explicit legacy/export adapter. The semantic final Dmb
arrays are still assembled; this is not a claim that every output list remains
on disk throughout linking. Final outputs remain durable; disposable cache
pages use atomic rename without per-page sync.

Resource layout identity now tracks exact alias partitions/dense indices,
with compatibility-checked CRC-row remapping on asset edits. Content checksums
are part of resource IDs and cannot simply be omitted from output. Unchanged
RSCs whose clocks changed through hardlink creation are reverified and reused,
rather than recomposed. These changes await benchmark H.

## Completed H benchmark

H succeeded: cold224.108s; unchanged0.434s; body58.270s; newproc84.669s;
newvar101.074s; default93.668s; asset16.425s; newresource100.577s;
freshcachedprocess0.162s; freshbody60.257s. Runtime correctness remains
unverified. Asset remapping bypassed procedure compilation as intended.
Body facts refreshed without header reload. Its remaining costs included
source persistence7.573s, output requested reads4.465s, and modified initializer
preparation18.976s despite unchanged generated code. Subsequent implementation
batches these initializer groups, persists compact origin runs and compressed
schemaV5 metadata, uses first-class COW word lists, and increases bounded
fragment lookahead. Shared semantic cache charges and trims were corrected.
These following changes await rebuild and benchmark I.

## Run I in progress and next implementation

Commit d5e778316a built the benchmark/CLI and all workspace binaries. No tests
were run. I so far: cold188.332s; unchanged1.828s; body26.428s. All three
requests succeeded; structural/fresh-process cases remain pending. This is
compiler timing only. Following edits stream cold origins directly into run
builders, compact cached subtree origins, and schedule independent resource
resolution observations through the shared bounded work scheduler. These
following edits are not part of the running I executable.

I completed successfully: cold188.332s; unchanged1.828s; body26.428s;
newproc71.855s; newvar67.758s; default73.067s; asset16.462s;
newresource81.198s; freshcachedprocess0.163s; freshbody47.798s.
No runtime tests. Body compiler10.630s; requested outputreads1.820s;
modifiedinitializers0.108s. Addproc compiler50.771s, owner5.639s,
defaults7.915s, declarationpreparation gap about19.6s. Following changes
reuse frozen initializer recipes, target semantic hydration by changedowner,
and avoid repeated per-literal lazy CAS reads during declaration preparation.
The typed outputpage/linkdirectory APIs are foundations and are not yet an
integrated license to skip semantic linking.

## Run J ongoing

Commit26bec4e4be builds benchmark and CLI. J first results: cold180.809s,
unchanged0.429s, body21.207s. Cold prepared manifest publication succeeded;
body requested exactly one211-byte authored source, persistence0.492s.
Body compiler8.873s; archivechecks2.090s; finalproof3.010s. Structural and
freshprocess results pending. Following work separates declaration base from
procedureoverlay and batches/compactly stores exact restored certificates;
those changes are not included in J. No tests or runtime runs.

J completed: cold180.809s; unchanged0.429s; body21.207s; newproc60.879s;
newvar60.944s; default53.434s; asset14.821s; newresource64.191s;
freshcachedprocess0.163s; freshbody40.091s. Every compilerrequest succeeded;
no runtimecorrectness claim. Nextprototype implements compressed declarationbase
reuse, bounded packed dependencycertificate pages in productionrestoration,
and Windows denywrite archiveleases during hardlinkpublication. Their build
and timing are pending; perowner declarationmutation recorder stillunfinished.

K executable built successfully from9367a4e017; new benchmark K is running.
No tests/runtime. Windows ArchiveLease private-field compile issue fixed using
the protected file metadata length. Next implementation records declaration
mutations and splits immutable procedurecode from linkedtypedprojections.
Current ListWords is Owned/Shared; code hydration remains necessary for existing
semantic readers and is not claimed eliminated by directory metadata alone.

K completed: cold190.294s; unchanged0.441s; body20.928s; newproc64.278s;
newvar60.393s; default56.948s; asset15.032s; newresource68.321s;
freshcachedprocess0.180s; freshbody33.954s. Packed82438certificates
restored5.223s, nolegacyreads (previouslegacy16.571s). Coldregression
approximately9.5s; investigate packedpublication overhead. Declarationbase
missed addproc because ordinaryclass-qualified constants conservatively
observedallprocdeclarations; nextcode uses exactabsolute target dependencies.
Following literaldeclarationoperation replay and filename-precise journal
namespace watches awaitbuild. No tests or runtime validation.

L completed from6dade9120d, cache/output movedtoE: dueC: headroom:
cold232.619s; unchanged0.470s; body26.950s; newproc57.582s;
newvar89.480s; default84.263s; asset16.063s; newresource95.744s;
freshcachedprocess0.161s; freshbody38.405s. All compilerrequests succeeded,
no correctness/runtime tests. This is a regression. Diagnosed recorder sparse
HashMap eviction scans, full-class operation hashing, and worstcase splitcode
job weights causing four hydration sessions pernormalwindow. Nextprototype
uses FIFO, typedfieldwrite projection, exactcodeword-count scheduling,
compressedcodeobjects and one sharedObjectWitness core. Archive snapshot
metadata reuse with freshstamp verification is implemented awaitingbuild.

M completed from 3a6de7dc83, with a fresh uncompressed C: cache:
cold 220.718s; unchanged 0.426s; body 22.662s; new proc 49.662s;
new var 109.126s; default 69.159s; asset 21.479s; new resource 80.935s;
fresh cached process 0.157s; fresh body 33.740s. All compiler requests
succeeded. No Rust tests, DM tests, or runtime validation were run.
New-var invocation preparation alone took 48.608s despite reusing all
68,411 authored bodies. The following prototype retains compact invocation
handles, rebases procedure-owned typed rows, and uses canonical source
emission recipes. Its first Cargo build passed; timings remain pending.
Packed certificates now use one publication representation, with legacy
reads and oversized-candidate fallback retained. That change awaits build.

N completed from 088ca8b935 (before packed-only publication): cold186.715s;
unchanged0.573s; body22.734s; newproc48.600s; newvar75.454s;
freshcachedprocess0.152s; freshbody34.933s. The focused benchmark omitted
asset/default/resource cases. All compiler requests succeeded; correctness
and runtime remain untested by instruction. Cold improved34s versus M;
body edits were effectively unchanged. Next build contains packed-only
certificates with dual-head invalidation, stable32MiB procedure projections
inside the existing64MiB payload cap, source-edit endpoint validation,
guarded archive composition, frame persistence independent of decoded cache
capacity, and staged pool pressure preserving reuse handles before restorable
PreparedProc payloads. Measurements for those changes are pending.

O completed from0bb6370be6: cold168.498s; unchanged0.486s; body23.000s;
newproc47.572s; newvar79.931s; asset14.867s; freshcachedprocess0.159s;
freshbody32.229s. All compiler requests succeeded; no tests/runtime.
Guarded unchanged-entry RSC composition3.146s versus earlier~7–8s.
Retained projection hits remained0: the aggregate pressure policy discarded
all67MiB of auxiliary payloads when only46MiB needed reclaiming.
Next checkpoint builds successfully and trims transient/retained recipes
partially to the actual excess, accounts a bounded2MiB weak shared artifact
index across sessions, composes relative closed literal/arithmetic/list
variable recipes, and stores preprocess blobs transactionally in bounded
2MiB batches with lazy32-key/4MiB raw hydration. Timings pending.

P completed from066ddd5a76: cold176.724s; unchanged0.481s; body24.844s;
newproc62.441s; newvar85.166s; default68.930s;
freshcachedprocess0.165s; freshbody40.290s. Asset/resource cases omitted.
All compiler requests succeeded; no tests or runtime validation. These are
regressions versus O, despite improved declaration-recipe reuse. Newvar reused
all68,411 authored bodies, but invocation preparation still cost14.857s;
body edits read/hydrated17.9MB of unchanged code and spent4.615s validating
inputs. Prepared cold persistence cost7.111s. The next implementation removes
unchanged-source content reads from identity traversal, uses direct immutable
invocation frames, and routes publication through a first-class wire image.
Wire-image serialization alone does not eliminate initial native hydration;
scoped physical composition must also migrate before that claim is valid.

Q completed from4aa4fc6325: cold230.110s; unchanged0.736s; body28.146s;
newproc66.786s; newvar89.180s; default64.187s;
freshcachedprocess0.167s; freshbody39.835s. Asset/resource cases omitted.
All compiler requests succeeded; no Rust/DM tests or runtime validation.
This does not meet the targets. Other unrelated builds and DreamDaemon worlds
were active on this shared machine; these measurements are not an isolated
performance comparison. No unrelated processes were stopped. Current native
compile output still hydrates code before converting to WireImage. The next
checkpoint implements actual physical assembly, persistent per-owner symbolic
binding roots, immutable bounded authored-source packs with transactional
range descriptors, and symbolic class-property writes across changed IDs.

## Addressed assembly checkpoint (implementation, pending build)

Canonical production now returns a physical WireImage directly. Procedure replay can append verified disk code handles, and indexed raw relocation checks digest, layout and old operands before rewriting changed references. Native Dmb consumers explicitly materialize at the compatibility boundary. Noncode list validation uses the same typed assembly interface.

Owner binding maps use persistent owner roots. Authored source persistence groups immutable blobs into bounded packs with range descriptors. Declaration replay stores compact symbolic variable and class-property recipes, binding current allocation IDs on replay. No Rust tests or DM/runtime tests were run; the next compiler benchmark must determine whether these migrations improve actual DeepQuarry timings. Q measurements remained far above the iteration target.
Addressed assembly checkpoint Cargo CLI/example build passed with -j1. Integration fixes covered assembly decoding errors, persistent delta signatures and compatibility early-return conversion. Namespace composition now preserves covered candidate proofs through file-only proof merges. No tests or runtime checks were run; R benchmark is next.

## R prototype benchmark interruption

895e48836c baseline request failed after 91.153102s with unresolved /world Genesis. This is not a successful cold-build timing. Owner-root derivation enumerated physical classes and missed the semantic /world owner; the followup now admits authored owners without class rows explicitly and advances owner cache schema to v2. Trace isolated defaults at 14.851s (ownerplans4.530, semantic2.077, operation-prefetch1.099, wire7.115) before later failure, and owner roots2.645s. These are diagnostic stage measurements only. R cache was compressed after the process exited, preserving contents.

Next implementation streams encoder pages directly to immutable disk objects, composes DMB CAS once under a guarded file receipt, and publishes a new generation by protected hardlink or verified copy. Owner eviction now subtracts stored admission charges; field-type derivation shares the main bounded owner-plan window, eliminating the earlier point-read prepass.
Followup streaming/source-bucket/semantic-world-owner checkpoint built successfully (-j1 CLI and iteration example, 3m20s). S benchmark uses fresh uncompressed cache and output directories on E to preserve C disk headroom; measurements should be interpreted with that storage location recorded. No Rust or DM tests were run.

## S prototype benchmark interruption and followup

S (e57c770193, fresh uncompressed E cache/output) passed the former Genesis failure but aborted at procedure output54272/68411 with allocation failure under the enforced3GiB process budget. It did not publish a baseline artifact; no valid cold/edit timings are available from this run. The trace reached118.458s within native compilation before aborting. Do not compare this failure as a completed compile.

Followup normal code persistence removes duplicate compressed word blobs when a verified wire leaf exists. Fresh main procedure/helper code now stages immediately into addressed output slots and reuses that same leaf in fragment metadata; resident words are a fallback only when optional disk staging is unavailable. Added Windows private/working/peak-commit phase observations to diagnose remaining memory growth. Name inheritance now uses a generation-local parent-chain memo and native-child adjacency. Source inventory buckets are computed once and Arc-identical origin maps reuse published origin SHA via weak provenance. No Rust tests or DM/runtime tests were run.
Memory-focused followup CLI/example build passed (-j1, 2m02s). T reruns the same3GiB cap with private/working/peak-commit procedure-phase traces; no tests/runtime validation.

## T memory diagnosis

T c6cfe4579f again exceeded the unchanged3GiB enforced budget before baseline publication. The first procedure-phase sample was already2195.1MiB private; at4096 procedures2317.3MiB, at31744 about2820MiB, and at54272 3062.6MiB. Native stage reached107.829s at54272, but this remains a failed build, not a cold-build result. There are still no successful new iteration timings to report.

The graph96MiB decoded budget evicts prepared envelopes, while Salsa inputs, tracked edges and witness/reverse metadata remain generation-wide. Next implementation bounds that validation frontier with persisted exact certificates and compact reverse edges, retiring Salsa epochs in bounded source-order windows. Dirty or untrusted records must retain invalid locators. Earlier stage memory samples will separately locate the pre-procedure2.2GiB live/transient peak.
Bounded validation frontier plus early phase/live graph memory traces built successfully (-j1 CLI/example, 2m05s), pending U compiler benchmark. No tests/runtime validation.

## U diagnosis and publication bug

U a3d394a8b2 finished the full native procedure phase within3GiB after bounded Salsa retirement, then failed publication on src/dmb.rs2411 (streaming string encryption indexed a buffer already flushed by raw()). Native compiler phase160.320s is a nested diagnostic, not a successful end-to-end compile. The followup encrypts strings before streaming via reused64KiB scratch and preserves the key across chunks.

U stage memory isolates the preparation regression: owner binding roots start863.2MiB and complete1983.5MiB (+1120.3MiB), although root accounting charged26.7MiB. im OrdMap/OrdSet nodes reserve64 slots even when empty; each owner had five maps and two sets (~22KiB×46693 owners). Compact Arc<BTreeMap/Set> owner-local payloads will replace those fixed-size inner containers; persistent outer indexes stay. No successful current cold/edit timings are available until a baseline artifact publishes.
CompactMap/CompactSet owner-local copy-on-write B-tree wrappers are implemented beneath persistent im outer indexes; owner root schema advancesv3. Pending build and V benchmark. Obsolete compiler package variants were cleaned from isolated E Cargo target (2.3GiB recovered), with m-u benchmark executables preserved; inactive executable archives/caches compressed without deleting contents.
Compact-owner collections and bounded encrypted-string streaming checkpoint built successfully (-j1 CLI/example, 3m08s). V captured executable is next; no tests/runtime validation.

## V measured memory improvement and Windows receipt followup

V b1efd9a0e8 again failed baseline publication, this time safely with composed DMB changed before guard acquisition. Native phase149.699s and serialization5.898s are nested diagnostics, not successful end-to-end timings. Windows finalizes a write/change stamp when the writable handle closes; comparing that earlier stamp against the reopened read guard rejected a legitimate file. The next receipt keeps the original private shareREAD|DELETE read/write handle alive (no API exposes writes). Stamp/copy observers shareWRITE to coexist with that handle, while its share mask still excludes all external writers; existing CAS guards remain read-only/write-denying.

Compact owner inventories reduced binding growth from+1120.3MiB (U) to+68.8MiB (V,863.6→932.4), removing~1051MiB. Invocation completion1078MiB; final reference validation peak1953.1MiB. Cold prepared/source persistence2.094s (authored CAS0.802, expansion0.803, source pages/manifest0.481, origin0.007). Optional owner-root retention cleared at existing32MiB cutoff under honest accounting; unchanged body uses skeleton, structural root retention needs future adjustment based on measured cases.
Original guarded DMB file lifetime followup built successfully (-j1 CLI/example,2m16s). W benchmark is next; no tests/runtime validation.

### W checkpoint: guarded publication succeeds
Captured HEAD 2136f9712d, two compiler workers, 3072 MiB process cap, DeepQuarry CITESTING fixture, E: cache. Successfully published baseline 204.217332 s, unchanged 0.239146 s, body edit 23.820318 s (one authored procedure lowered, 68410 reused), add-proc 73.186483 s (one lowered, 68411 reused), add-var 99.013720 s (zero lowered, 68411 reused). Remaining cases are still running. These are compiler/output benchmark results, not semantic or runtime validation; no Rust or DM tests were run.
Body-stage attribution: compiler 14.018 s, output 8.976 s; metadata read 2.171 s, decode 1.209 s, replay 1.014 s; serialization 4.915 s. 68169 metadata-only code reuses and zero code hydration. This proves that procedure lowering is incremental, while shared declaration preparation and final output traversal still impose significant work.
Follow-up implementation: immutable invocation templates with recorded declaration observations; bounded output read windows indexed by actual code leaves rather than all list rows; borrowed ordered include-unit comparison for unchanged manifest structure. No near-instant structural-edit claim is justified at this checkpoint.
W remaining completed measurements: change-default 65.109107 s, fresh-process unchanged receipt 0.309440 s. Fresh-process body-edit was intentionally terminated at 129.482 s after traces showed every procedure rebuilding (zero reuse through 5120 authored procedures); this is an aborted diagnostic run, not a completed cold-edit timing. Root cause: disk fact inputs begin unknown, resolving them marks all readers dirty even when persisted exact witnesses match. Validation-window compaction rejected those dirty candidates and forced lowering. Follow-up reconciles dirty flags only through the existing complete Salsa candidate query after fact resolution. W receipt hashes and full diagnostic logs remain preserved; its cache is being compressed without deleting contents to recover disk headroom.

### X checkpoint: declaration invocation query production migration
Combined CLI/example Cargo build passed (2m06s), no tests. Captured HEAD1a2583ff99 for benchmark X. InvocationPlan now separates immutable Arc<InvocationTemplate> from physical static-ID allocation. Exact-valid static-free template admission precedes syntax/signature restoration and ancestor traversal. Metadata queries record parent links, named declaration presence/absence, native fallback and resolved ancestor identity through one observed-dependency path validated by Salsa. Static-bearing templates allocate current slots separately. Optional invocation admissions are reclaimed before the frozen declaration prefix under pool pressure; owner inventories evict bounded entries instead of clearing the entire cache. Physical serializer lookahead and metadata-only fragment retention, exact cold-candidate reconciliation, and page-arena interning are included.
Benchmark X uses a fresh E: cache, two workers, 3072 MiB cap, baseline/unchanged/body-edit/add-proc plus fresh-process cached/body cases. Remaining work includes restoring persisted metadata-query records directly on cold admission, bounding obsolete weak/negative handles, and auditing current source diagnostics. This is a production-path migration checkpoint, not a declaration that the entire incremental compiler or semantic parity is complete.
X baseline aborted before output: invocation metadata fingerprint attempted JSON serialization of enum-keyed BTreeMap and lower_cache::shared_binding_fingerprint panicked (key must be a string). Native trace reached invocation preparation start at39.614 s; this is not a completed cold-build timing. Correction uses a deterministic ordered sequence of observation pairs in fingerprint inputs. Captured X executables and failure logs remain preserved. No tests/runtime were run.
Y completed outputs: cold(empty cache)221.753595 s; unchanged0.240376 s; body-edit20.171757 s (one lowered,68410 reused); revert-body5.798225 s. Add-proc was intentionally stopped to avoid exhausting E: (125 MiB free), so Y structural and fresh-process phases have no completed measurements. Cache/logs preserved; content-preserving compression reduced4,536,937,777 logicalbytes to1,747,006,333 storedbytes. Subsequent benchmark checkpoints will reuse this disk cache and explicitly distinguish existing-cache startup from empty-cache cold compilation.
Y body still discarded216 MB frozen prefix after optional trims, leaving~570 MB over512 MiB pool budget. Serializer code reads:69 windows,37,693,472 bytes,1.750 s of store-read time. Cold invocation migration derived100,639 metadata records and regressed invocation preparation; optional persistence batching and repeated encoding are being corrected. Follow-up: metadata records encoded once with8 MiB pending batches, addressed initializer source handles read only after graph misses, compact internal certificate digests, separate semantic metadata value identity/proof content identity, and a bounded background physical-code reader overlapped with serial encoding. None of these follow-ups has a completed benchmark yet; no tests/runtime validation.
Z (captured24cd84186e) was intentionally terminated with no completed output when E: reached zero free bytes. It used the NTFS-compressed Y cache; default-plan prefetch3.693 s and symbolic-owner restoration37.655 s versus Y fresh0.881/11.038 s are storage-confounded, not a valid compiler-regression comparison. Invocation persistence11 batches45.163 s confirms database I/O must be controlled. Source handles addressed3,745,322 bytes; skeleton heap201,887,805 bytes, saving only2.4 MB, so source migration alone cannot solve prefix eviction.
Inactive task-owned W/U/V caches have been relocated intact to D:/dmb-benchmark-archive/20261002-{w,u,v}-cache to recover SSD headroom; their generation receipts and logs remain at original E: output directories. T cache relocation is in progress. These are reversible content-preserving archives, not deletion. Before another benchmark, active Y .redb files will be uncompressed after checking actual allocated storage and free space. The archive paths must be used when locating old cached artifacts; original E: cache paths no longer exist for archived cases.
Storage control completed: W/U/V/T inactive caches are intact at D:/dmb-benchmark-archive/20261002-<case>-cache. Y active21 redb databases were uncompressed after checking logical5,118,029,824 bytes versus actual1,480,863,744 allocatedbytes and preserving1 GiB worst-case headroom. Sparse database storage remained sparse; final E: free4.49 GB. AA benchmark runs the exact same captured Z executable24cd84186e with uncompressed Y databases, full structural/body/fresh-process cases, two workers and3072 MiB cap. This distinguishes storage effects from subsequent compiler edits; AA initial baseline uses existing cache, not empty-cache cold.

### AA same executable, uncompressed recovery cache

Captured Z executable (24cd84186e), existing Y cache with redb compression removed: initial cached-process build 1089.506850 s; unchanged 0.257350 s; body edit 21.943694 s; body revert 5.921199 s; add proc 71.589184 s; proc revert 31.949594 s. Aggregate retained phase hit its 1800 s timeout during add-var. No add-var/default or fresh-process result. Receipts/logs preserved at E:/dmb-bench-20261002-aa. This is not a clean empty-cache cold measurement and not a correctness result.

Body validation/serialization wall 2.471 s, producer code I/O 1.931 s: bounded producer overlap reduces serialization wall compared with W's 4.915 s. Initial symbolic declaration preparation 404.941 s and add-var default-plan prefetch 43.882 s expose a storage problem. dm-store creates/drops redb for every access; redb recovery and allocator shutdown are being investigated and instrumented rather than attributed to compression alone.

The failed disk-full cache is being preserved intact at D:/dmb-benchmark-archive/20261002-y-cache before the next clean SSD benchmark. Source-cache paths move; existing published hardlinked generations and all benchmark receipts remain at their original output paths. No test or runtime execution.

### AB bounded sessions, shared census, metadata pages

Commit52d900ca6a plus initializer windows75e0a36f73; CLI and iteration example Cargo build succeeded, no tests/runtime. Captured executables tools/dmb/target/bench-executables-20261002-ab. Clean SSD cache E:/dmb-bench-20261002-ab-cache; receipts E:/dmb-bench-20261002-ab. Workers2, memory3072MiB.

Cold empty-cache build172.980094s; unchanged0.258507s; one body edit15.595985s (1 lowered/68410 reused); revert4.843415s. Fresh process unchanged0.258117s; fresh process with body edit25.085319s (1 lowered/68410 reused). Benchmark success means compiler publication, not semantic/runtime parity. Cold restart now preserves exact candidate reuse. Warm body reused frozen declaration skeleton in1.089s: shared allocation census prevented its prior eviction. Metadata read0.286s, decode1.537s, replay0.928s; body bytecode validation/serialization1.205s. Some output metadata recipes still rebuilt (242 built/68169 reused) despite semantic lowering reuse; targeted range composition remains required.

Old Y recovery cache archive completed at D:/dmb-benchmark-archive/20261002-y-cache; E old cache path removed by content-preserving Move-Item. SSD free space after move9.9GB, after fresh AB cache roughly4.8GB. Archive never used as active benchmark storage.

## Next integrated checkpoint (2026-10-02)

- Generic packed indexes now use binary locator views and bounded exact-witness validated-index reuse. Transactional current-bucket reads remain required; this does not pretend that raw bucket IO is eliminated.
- Invocation fragments and metadata/templates share the generic packed-record path, retaining optional legacy fallback.
- Physical procedure/variable snapshots can compose exact unchanged addressed slices without rewriting table rows; relocated row fingerprints remain mandatory after semantic and debug witnesses authorize replay. Snapshot capture visits physical order to keep decoded page caches bounded and avoid lexical-order page thrashing.
- Typed ranges and final serialization consume bounded 1024-row windows, with one hydration per overlapping page rather than one lock/read per row.
- Iteration benchmark reports compiler-child peak private/working memory and cumulative Windows IO counters. Timing-only native compilation; no Rust tests or DreamDaemon.
- AB cache preserved at D:/dmb-benchmark-archive/20261002-ab-cache; active timing caches remain on E SSD.
- Remaining explicit gaps: full procedure metadata traversal/decode and cold declaration preparation, durable physical-row directory restoration, structural-edit target, and correctness gates. No completion claim.

## AD timing checkpoint, bfd07ee6c6 (regression, not completion)

Cold empty SSD cache245.714s, unchanged0.328s, warmbody25.590s, revert7.298s, freshprocessunchanged0.346s, freshbody39.016s. Edits still1lowered/68410reused. All native publication completed; no tests/runtime validation.

Physical directory recorded0hits. Auxiliary frontend trimming cleared it before replay (baseline804.2MiB beforetrim /683.5MiB after against512MiB limit); optional in-memory directory alone was ineffective. Durable restoration is now coded but unmeasured. Warm directory capture1.120s; metadataread.296s/decode1.920s/replay1.648s; compiler16.050s andserialization2.173s. Cold declarationallocation75.785s, template/metadata persistence4.337s (11batches). No claimed speedup; next checkpoint must show real rowhits and improved walltimes.

## AE timing checkpoint, f6f66f7ff9 (still regressed)

Cold285.471s, unchanged.283s, warmbody27.555s, addproc73.883s, addvar189.608s, default93.919s, freshprocessunchanged.271s, freshbody89.277s after structural cases. All publication succeeded; body1lowered/68410reused; addvar/default0lowered/68411reused. No Rust/DM tests.

Durable physical reuse now OBSERVED: warm body68169hits,0published,capture.319s; addproc68169hits,2published,.391s. Structural dense list/variable IDs shift legitimately, so allrowfingerprints differ. Physical directory publisher then merged256full locator buckets on every1024-record publication: addvar68411published/37.955s capture, default68411published/16.883s. Root raised publication WINDOW (not immutablepage shape or retainedcache cap) to16384records/8MiB; generic pages remain1024. This reduces fullindex rewrites from67 toabout5 and must be measured next. Latest mutable perproc directory can displace earlier layout; multi-version/relocatable row recipes still needed.

Next production source migration removes full declaration AST clone via borrowed source shards and derives semantic plans only for changed shards/owners. Owner output recipes now reuse via existing ObjectWitness system, generic fallible AssemblyImage helpers. Complete graphbindingcontext proof covers deterministic shared/private resolver inputs and declaration image; durable compactgraph context should avoid restart-wide header/fact reconstruction only for exactmatching proof. New paths coded, unbuilt/unmeasured at this note.

## AF checkpoint: source-order migration failure

The captured AF binaries built successfully but the native DeepQuarry baseline failed after146.396s before publication: acceptable_fruit_types was unresolved in a generated GLOBAL_LIST_INIT body. This is a failed compilation, not a cold-build timing. Borrowed AST items preserve fragment-local spans; the authored pending list still sorted by item.span.start while current procedure descriptors used source order. The fix sorts by proc.span().start (source offset plus local span), restoring owner/body pairing. Annotation diagnostics also use absolute spans. No tests or runtime ran.

AE attribution correction:82.164s was a cumulative trace timestamp, not invocation-preparation duration. Index completion55.952s to plan completion82.499s gives about26.55s; metadata/template persistence7.921s. The broad restore remains expensive, but cumulative timestamps must not be reported as stage durations.

Next source changes select the physical row directory by exact complete binding context. Structural layouts retain separate named directories, so reverting a declaration can recover its previous physical rows instead of replacing a single latest location per procedure. This is candidate selection only: every replay still checks the current row fingerprint and semantic/debug witnesses. Historical directories remain on disk; bounded retention/GC policy remains outstanding. Publication uses bounded16384-record/8MiB transactions with1024-row immutable pages. Unbuilt and unmeasured at this note.

The follow-up migrates DeclarationBase and FrozenSkeleton from NativeDmb to WireImageBuilder physical snapshots. Owner/default/static emission and metadata queries consume AssemblyImage typed proc/variable/list readers with propagated I/O errors. Immutable typed table segments are shared on snapshot composition; resident list words freeze to shared allocations. Portable physical manifests restore typed page references through existing stores instead of materializing every procedure/variable row. Class and string metadata remain resident arrays, and whole-project invocation preparation/range replay are still pending. This source checkpoint has not yet built or produced timing results.

Combined physical-prefix checkpoint Cargo CLI/example build succeeded (3m17s), no tests. Captured executables:tools/dmb/target/bench-executables-20261002-ag. Corrected remaining generic world/grid/header accessors and propagated static-variable append failure. AG native timing benchmark will use a fresh SSD cache,two workers,3072MiB process cap; no results yet.
