# Native DM Compiler Design

Revision 5, 7 October 2026. Status: **in implementation** on `codex/native-v2`. The plan in §9 was
revised after the review in `archive/REVIEW_20261007.md`, and that plan is binding. Supersedes
`ARCHITECTURE.md` and
`REVISED_ARCHITECTURE.md` for the incremental layer, persistence, output publication and process
model. The format notes (`FORMAT.md`, `crates/dmb-opendream/doc/BYTECODE_ISSUES.md`, `OPENDREAM_OPCODE_MATRIX.md`,
`CLIENT_HEADER_PROBES.md`, `crates/dmb-opendream/doc/TRANSLATION_GAPS.md`) remain authoritative for the BYOND format.

This design replaces the architecture on `codex/compiler-architecture`. It keeps the parser,
preprocessor, code generator and DMB writer that compiled the whole project on 1 October. It
replaces everything built around them since then: the disk-backed graph, the database, the
memory budgets and the proofs.

Revision 4 incorporates Astra's second review and a self-review. Recorded reads are now checked
per dependency domain. The object tree is split into a reusable semantic tree and a per-build
occurrence table, and `set` metadata counts as declaration content. The oracle compiles the
captured snapshot. Pair acquisition and eviction are synchronized, and pair stores live on each
drive. Orders the game can observe must match DreamMaker. Diagnostics are replayed on every
build, and builds of one worktree are serialized. The baseline is compared through normalized
error identities, and every budget includes validation and publication costs. Appendix B lists the
changes.

Revision 5 reacts to the first measurements. Phase 1 produced a full deterministic compile in 33 s.
The stages meant to rerun cheaply on every build cost about 55 s, 10–50× the §6 hypotheses, and
the disk cache work built on top of them made incremental builds slower than cold ones. Revision 5
makes stage throughput the next phase, requires a profiler that needs no elevation, judges
performance by CPU time rather than wall time, moves the daemon ahead of further disk-cache work,
and freezes the cache code until then.

Implementing agent: read `archive/REVIEW_20261007.md`, then §5 (correctness contracts), §8 (engineering
rules) and §9 (plan) before writing code. Work resumes at the Phase 0 close-out in §9.

## Acceptance targets

These are acceptance criteria for the phases, derived from first-principles estimates. None has
been measured on the new design. They include validation and publication costs.

| Scenario | Target |
| --- | ---: |
| Procedure body edit, daemon running | ≤ 1 s |
| New var or proc, or a changed default, daemon running | ≤ 2.5 s |
| Cold build, empty cache | ≤ 20 s |
| Body edit with no daemon, warm disk cache | ≤ 1.5 s |

DreamMaker takes about 2 min 11 s for each of these on this machine, because every DreamMaker
build is a full build.

## The design in eight decisions

1. Compiler state is worked on in memory. A long-lived daemon per user keeps it warm for every
   worktree. A one-shot CLI maps the same state from the disk cache and is hypothesized to be about
   twice as slow per edit. Disk holds the outputs and that cache.
2. Three kinds of memo, and no others: include-region expansion, procedure lowering and map
   parsing. A memo entry is reused only when its key matches exactly and every read it recorded
   from outside its key still gives the same answer in the domain it came from.
3. Every other stage (include order, the semantic tree, the occurrence table, linking, encoding)
   reruns in full or is reused whole. Tracking their parts would cost more in code and bugs than it
   saves.
4. Lowered code is relocatable: it names strings, types and procs symbolically. Each build links a
   fresh DMB. Every order the game can observe matches DreamMaker; every other order is canonical.
   No ID ever depends on edit history.
5. The disk cache is append-only. Segments are self-contained, validated before use and never
   modified. There is no shared mutable index, no transaction and no repair.
6. Outputs are published as immutable DMB+RSC pairs in a store on each drive. Nothing that starts a
   world can see half of one pair and half of another.
7. The correctness oracle is a cold native build of the same captured snapshot, compared byte for
   byte, diagnostics included. Parity with DreamMaker is behavioral: every difference is on a
   divergence list with an explanation.
8. Performance figures are hypotheses until measured on a release build, stage by stage and end to
   end, under a sampling profiler, after the oracle has passed.

---

## 1. Starting point

Measured on 6 October against the real project and this machine.

| Quantity | Value | Source |
| --- | --- | --- |
| Source | 5,694 included files, 45.0 MB of DM | `deepquarry.dme` on master |
| Procedures | about 65,000 | 65,002 in the 6 Oct native run |
| Types | about 44,000 | native table export |
| Strings, lists | 147,730 strings, 59,826 lists | native table export |
| DMB | 49 MB | worktree builds today |
| RSC | 218 MB, about 3,900 resources | worktree builds today |
| Machine | Ryzen 7 5800X (8 cores, 16 threads), 64 GB RAM, NVMe SSD (C:), SATA SSD (E:), HDD | this PC |
| Worktrees | Main checkout and `dq-wt/*` on E:; Codex worktrees on C: | this PC |

| Reference timing | Result | Notes |
| --- | ---: | --- |
| DreamMaker 516, full build | 2 min 11 s | Every build is a full build. The run reported 71 errors from a stale generated file, so treat this as approximate. |
| Native, 1 Oct, body edit with daemon | 3.24 s | Commit `ac1af55d1a`, 48,681-procedure snapshot. Compiling took 0.28 s; the rest was preprocessing, proofs and publishing. |
| Native, 1 Oct, cold rebuild | 104–131 s | Hot crates at `opt-level=1`, persistence on the critical path. Not yet profiled. |
| Native output, game test suite | 997 pass, 34 fail | DreamMaker output: 985 pass, 46 fail. **Not parity**: passing tests recorded runtime errors in 586 tests (native) vs 561 (DreamMaker); five shared failures differ in detail; one failure is native-only. See `FULL_SUITE_COMPARISON.md`. |
| Current branch, 6 Oct | no build in 20 min | 146 GB read, 93 GB written, 2.3 GiB peak memory. Another run panicked. 475 commits and about 150,000 lines of Rust since 2 Oct. |

What these establish: on 1 October the code generator was complete enough to compile the whole
project and run the full test suite, and a body edit took 3.24 s. The collapse in speed came from
the incremental layer added afterwards. What they do not establish is behavioral parity with
DreamMaker: the outputs differ in runtime errors and in several test details. This design keeps
the 1 October front end and code generator, replaces the incremental layer, and treats parity as
a tracked list of divergences (§5.3). A higher pass count is not evidence of parity.

### What to keep

Start from `ac1af55d1a`, the last commit with a green Rust test suite (1,199 tests) and the
3.24 s measurement.

| Crate or file | Decision | Notes |
| --- | --- | --- |
| `byond-dmb` | Keep | DMB and RSC reader and writer, with its format tests. |
| `dm-syntax` | Keep | Lexer and parser. Move to the symbol IDs of §3.3. |
| `dm-preprocess` | Keep core | Drop the leaf-include cache and its persistence. Rebuild around include regions and read recording (§4.1). |
| `dm-codegen-byond` | Keep lowering | Drop the projection caches and byte budgets. `Symbol { key: String }` and `Label(String)` become IDs. |
| `dm-compiler` | Mine, then rewrite | The semantic rules (object tree, defaults, initializers, header flags) live in `bootstrap.rs` (681 KB). Extract them into the tree and resolver crates of §3.8. Drop the graph, owner, receipt and page machinery. |
| `dm-analysis` | Keep the export, rebase it | The analysis export becomes a consumer of the read-only tree API (§3.8). |
| `dm-resources` | Keep | Asset identity and RSC entries. |
| `dm-output` | Keep encoding only | Drop generations, install journals and output proofs. Publication follows §4.8. |
| `dm-store`, `dm-work`, `dm-compiled`, `dm-host` | Delete | Replaced by the daemon (§3.1), the cache (§3.4) and a rayon pool. |
| Format notes | Keep | `FORMAT.md`, `crates/dmb-opendream/doc/BYTECODE_ISSUES.md`, `OPENDREAM_OPCODE_MATRIX.md`, `CLIENT_HEADER_PROBES.md`, `crates/dmb-opendream/doc/TRANSLATION_GAPS.md`. |
| `FULL_SUITE_COMPARISON.md` and its records | Keep | Seeds the frozen parity baseline (§5.3). |
| Dated benchmark and migration logs | Archive | Move out of the tool directory. |

---

## 2. Disk or memory

The current branch keeps intermediate results on disk because it gave itself a 2 GiB process
ceiling and one memory budget across six worktrees. That ceiling drove the disk-centric design.
Removing the cap alone did not make that design fast (the uncapped 20-minute runs still failed);
the per-record store is the problem.

### 2.1 Fetching versus recomputing

Recompute and fetch costs below are estimates; Phases 0 and 1 measure them.

| Unit | Recompute | Fetch from a per-record durable store | Fetch from memory |
| --- | --- | --- | --- |
| Lower one procedure | 20–100 µs target (up to ~1 ms in today's code) | 10–50 µs per read plus decode. Writes measured at 7.5 ms per transaction (651 s across 86,917 transactions in run BS). | about 0.1 µs |
| Expand and parse one include region | 0.2–2 ms | same as above | about 0.1 µs |
| Whole compiler state | 10–20 s (a cold build) | 50–100 ms to map 300–500 MB of cache segments, plus validating the records used; 0.3–0.6 s more if the OS file cache is cold | already resident |

A per-item disk cache can at best tie with recomputing. With durable writes it loses by two orders
of magnitude, which is what the 6 October runs show. Mapping whole segments wins, because no
record is decoded, locked or transacted.

### 2.2 Memory footprint

Estimates from the project's sizes. The first measurement (probe 40, 2 workers) was 3.0–3.5 GB
peak private memory per build, about six times this estimate. Phase 1 must bring it to 1.5 GB or
less (§6.0) and explain where it goes.

| Component | Scope | Estimate |
| --- | --- | ---: |
| Source text, by content hash | shared | 45 MB |
| Expansion memo: expanded tokens, declaration fragments, macro reads | shared | 150–200 MB |
| Lowering memo: symbolic code, relocations, resolver reads | shared | 80–120 MB |
| Map memo | shared | 20–60 MB |
| Symbol table | shared | 15–25 MB |
| Semantic tree, occurrence table, indexes and provenance | per session | 50–80 MB |
| Linked image and ID maps | per session | 60–80 MB |
| **One worktree** | | **0.45–0.6 GB** |
| **Six worktrees on mostly identical source** | | **1.0–1.5 GB** |

### 2.3 What worktrees share

Every shared store is keyed by content rather than by path or worktree, so anything identical is
stored once.

| Item | Shared when | In practice |
| --- | --- | --- |
| Include-region expansion | Same region bytes, and every read of incoming state gives the same answer | Two branches that each changed 20 files share the regions of the other 5,674. |
| Procedure lowering | Same full procedure occurrence and owner, and every recorded read gives the same answer | Shared even when the file around the procedure differs. |
| Test and server builds | Regions whose expansion never read a define that differs between them | Only 83 files mention `CITESTING` or `UNIT_TEST*` and 191 contain any `#if`; the two configurations should share most expansions (to be measured). |
| Branch switches | Any content seen before | Switching back to a branch built earlier should be mostly cache hits. |
| Symbols | Same text | A symbol's ID is a hash of its text, so processes agree on it without coordination (§3.3). |
| Output pairs | Byte-identical DMB and RSC on the same drive | Pairs live once per drive in a content-addressed store (§4.8). Pairs that differ only in DMB share their RSC file inside the store. |
| Semantic tree, occurrence table, linked image | Not shared | About 130–160 MB per session. |

### 2.4 Verdict

| Data | Lives in | Why |
| --- | --- | --- |
| Session working state (trees, linked image) | Process memory | Rebuilt or reused every build. |
| Memo entries and symbol texts | Append-only cache segments, memory-mapped, validated before use | Read on every build at memory speed. Survive restarts. Shared by every process and worktree. |
| DMB and RSC | Immutable pair directories in a store on each drive; worktree paths hold copies | DreamDaemon needs files. Pairs never change after publication (§4.8). |
| Source and resource files | Disk (they are the inputs) | Reread when their stamp changes. |
| Receipts, proofs, journals, generations, leases | Nowhere | Unnecessary once cached values never change and outputs are published as whole pairs. |

> **Persistence rule.** Cached values are written once, in a single batched segment at the end of
> a build, and read through memory maps after validation. Nothing is updated in place, nothing is
> fsynced, and there are no transactions and no shared mutable index. A cache miss is always
> correct. A segment that fails validation is ignored, never repaired.

### 2.5 Resource controls and idle memory

Per-component budgets are removed. A few coarse controls remain, so growth stays bounded:

- **Variants per memo key:** at most 4; the least recently used is dropped.
- **Concurrent builds:** at most 3 at once in a daemon; further requests queue.
- **Soft memory limit:** 4 GB of private memory by default. Above it, idle sessions are trimmed
  first, then unpinned heap entries are dropped. Mapped pages are left to the OS.
- **Idle trimming:** a session idle for 10 minutes drops its trees and linked image. Its next build
  pays to rebuild them (hypothesized 0.5–0.8 s, the same as a no-daemon build).
- **Exit:** after two idle hours the daemon exits. Nothing needs saving; the cache is already on
  disk.

> **Limit rule.** A limit may evict data or queue work. It may never switch a build to a different
> algorithm, skip a cache lookup, take a fallback path or change the output. The current branch
> recorded 13,409 fallbacks caused by a 4 MiB workspace limit; that class of behavior is banned.

New memo values start on the heap. After they are appended to a segment, the process switches to
the mapped copy and frees the heap one. Mapped pages are file-backed: the OS can drop them under
pressure without swapping, and processes mapping the same segment share one physical copy.

| Daemon state (estimates) | Private memory | File-backed, reclaimable |
| --- | ---: | ---: |
| Just built six worktrees | 0.8–1.1 GB | 0.3–0.45 GB |
| Idle more than 10 minutes | 0.1–0.2 GB | 0.3–0.45 GB |
| Idle more than 2 hours | 0 (exited) | 0 |

---

## 3. Architecture

### 3.1 Processes

- **`dmbd`**: one daemon per user. It owns the sessions and the shared memos and listens on a
  named pipe (`\\.\pipe\dmbd-<user>`; a Unix socket on Linux). The pipe's access list admits only
  the current user.
- **`dmbc`**: a thin client called by `build.ts`. It sends one build request (worktree root, .dme,
  defines, output paths), streams diagnostics and exits with the result, including the ID of the
  pair it published. It starts `dmbd` when none is running.
- **Version handshake.** If the daemon was built from a different compiler binary, the client asks
  it to retire. A retiring daemon refuses new builds, lets running builds finish, then exits; the
  client starts the new binary meanwhile. Rebuilding the compiler never kills another worktree's
  build.
- **Session**: one per worktree root, .dme and define set. It owns its input snapshot, semantic
  tree, occurrence table, linked image and the record of its previous build.
- **Session lock.** Every build of a session, from the daemon or from a no-daemon run, holds an OS
  lock on that session for the whole build. Two builds of one worktree never interleave.
- **Cancellation.** A new request for a busy session cancels the running build at the next stage
  boundary before publication. Publication itself (§4.8) is never cancelled.
- **Concurrency.** All sessions share one rayon pool, with at most 3 builds running at once. The
  shared memos are insert-only concurrent maps, and a value is never changed after insertion.
- **Lifecycle.** Idle trimming and exit as in §2.5. After a crash, the next `dmbc` starts a fresh
  daemon, which maps the cache and carries on.
- **No-daemon mode** (`dmbc --no-daemon`) runs the same pipeline in a one-shot process against the
  same cache. It is a supported mode for CI, scripts and anyone who prefers no background process.

```
 Sessions (one per worktree x define set; own mutable state)
 ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
 │ main checkout        │ │ dq-wt/items2         │ │ dq-wt/om2            │
 │ CITESTING defines    │ │ CITESTING defines    │ │ server defines       │
 │ trees, linked image  │ │ trees, linked image  │ │ trees, linked image  │
 └──────────┬───────────┘ └──────────┬───────────┘ └──────────┬───────────┘
            └──────── lookups and inserts ────────────────────┘
 Shared stores (immutable once written, backed by the mapped cache)
 ┌──────────────────┐ ┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
 │ Expansion memo   │ │ Lowering memo    │ │ Map memo     │ │ Symbol table     │
 │ per include      │ │ per procedure    │ │ per .dmm     │ │ IDs = text hash  │
 │ region           │ │ occurrence       │ │              │ │                  │
 └──────────────────┘ └──────────────────┘ └──────────────┘ └──────────────────┘
            │ one self-contained segment appended per build
 Disk
 ┌───────────────────────────────────────┐ ┌────────────────────────────────────┐
 │ Pair store per drive: immutable       │ │ Cache segments: append-only,       │
 │ DMB+RSC pairs; run slots link them;   │ │ validated, mapped read-only by     │
 │ worktree paths hold copies            │ │ every process                      │
 └───────────────────────────────────────┘ └────────────────────────────────────┘
```

A no-daemon build is one session in a short-lived process using the same stores.

### 3.2 The build pipeline

Times are hypotheses for a body edit with the daemon running, and for a cold build. They include
validation and publication.

| Stage | Unit | Memoized | Reruns when | Body edit | Cold |
| --- | --- | --- | --- | ---: | ---: |
| S0 Inputs | all files and resource search folders | no | every build | 50 ms | 0.3 s |
| S1 Include regions and macro directives | one ordered pass | no; replays recorded effects | every build | 10 ms | 0.3 s |
| S2 Expand regions and parse | include region | **expansion memo** | region bytes changed, or a read of incoming state changed | 5 ms | 2 s |
| S3a Semantic tree | whole tree | no | the ordered sequence of declaration skeletons changed | skipped | 0.5 s |
| S3b Occurrence table | all declaration occurrences | no | every build | 20 ms | 50 ms |
| S4 Lower procs and initializers | procedure or initializer occurrence | **lowering memo** | occurrence changed, or a recorded read changed in its domain | 5 ms | 3–8 s |
| S5 Maps | .dmm file, then all cells | **map memo** | map changed, or a recorded read changed in its domain | skipped | 1 s |
| S6 Resources | resource set | content IDs cached by stamp | every build | 5 ms | 1 s |
| S7 Link | whole image | no | every build with a change | 200 ms | 0.5 s |
| S8 Encode, hash and publish pair | whole DMB; RSC if changed; worktree copy | no | every build with a change | 200 ms | 1.3 s |
| **Total** | | | | **≈ 0.5 s** | **≈ 10–15 s** |

A stage earns a memo when three things hold: its per-item work costs at least 10× the cost of
computing the key and checking the recorded reads; a typical edit touches a small fraction of its
items; and its result can be keyed by content. The other stages fail at least one test:

- **S0 inputs** is the change detection itself. Its stamps are kept, the only caching it can use.
- **S1 include regions** is a sequential pass that replays recorded effects (hypothesized ~10 ms).
- **S3a semantic tree** is reused whole when the ordered declaration sequence is unchanged. When it
  changed, inheritance means one change can reach thousands of types. An incremental version is
  the first candidate in §6.4.
- **S3b occurrence table** is a linear pass over the region list; caching it would save little.
- **S6 resources** caches content IDs by stamp, a small cache of its own.
- **S7 link** assigns IDs across the whole program. One new string shifts every later ID, so a
  cached linked procedure would almost never be valid.
- **S8 encode** obfuscates strings by their byte position in the file, so a change early in the
  file changes everything after it.

Three kinds of memo is a starting point, not a fixed limit. Another is added only when a profile
shows a stage dominating and the memo paying back 10×.

### 3.3 Data model

- **Symbols.** Every name, type path and string literal is identified by a 64-bit hash of its
  text, with a symbol table mapping hashes back to text. Separate processes writing to the shared
  cache agree on every ID without coordinating. Inserting a symbol checks for a collision, which is
  an error, not a silent merge. Hot data structures never hold `String` keys.
- **Arenas.** Tree nodes, declarations and lowered code live in vectors indexed by `u32` IDs.
- **Hashes.** xxh3-128 for content addressing; no SHA-256 anywhere. NQCRC only where the BYOND
  format requires it.
- **Symbolic code.** A lowered procedure is a word array plus a relocation list of
  `(offset, SymRef)`. A `SymRef` names a string, type, proc, var, constant list, resource or line
  delta. No table ID ever appears in a memo value.
- **Relative positions.** Memo values store positions relative to their own unit: lines relative to
  a procedure's first line, offsets relative to a region's start. Absolute file and line come only
  from the current occurrence table at link or report time. Inserting a line above a procedure
  does not force it to be lowered again, and a region shared by two files reports locations in the
  file that included it.
- **Canonical paths.** Filesystem access and first-visit include suppression use normalized host
  identity. Emitted `__FILE__` and its provenance retain the relative include spelling observed
  from DreamMaker: separators become `/`, but resolvable `..` components remain. Do not substitute
  the host identity into emitted source strings. Resource archive naming follows its separate
  search/alias contract. Windows and Linux builds of the same snapshot produce the same bytes;
  `PREPROCESS.md` defines these representations and their captured fixtures.

### 3.4 The disk cache

- **Location.** One directory per user on the configured cache drive, shared by every worktree,
  define set and process. On this machine the default is `E:\.dmbd\cache\` (decided 7 October;
  C: ran out of space during population). `DMB_CACHE_DIR` overrides it; on Linux the default is the
  XDG cache directory. Memory maps work across drives, so one cache serves worktrees on every drive.
  Population checks free space first and reports a shortage as an error, never by skipping records.
- **Segments.** Each build that computed something new writes one segment to a temporary name, then
  renames it to `<segment-id>.seg`. A segment exists for readers only once renamed. The set of live
  segments is the directory listing; there is no manifest.
- **Self-contained.** A segment includes the text of every symbol its records reference, and its
  records reference nothing in any other segment. Ignoring a segment therefore loses only its own
  entries; nothing elsewhere dangles.
- **Records.** Memo entries (expansion, lowering, map) with their diagnostics, symbol texts,
  resource content IDs, and session records (one worktree's last input snapshot and published pair
  ID).
- **Validation.** The segment header (magic, stage versions, length) is checked when the segment is
  mapped. Each record carries its own xxh3 checksum and is validated (checksum, then rkyv's
  bytecheck) before its first zero-copy access, so offsets and lengths are known to stay in bounds.
  Only records a build actually uses are validated, and that cost is part of the build's reported
  time. A failed record causes the whole segment to be ignored, with the reason logged.
- **Versions per stage.** Every record carries the version of the stage that produced it
  (preprocessor, parser, lowering, maps). Changing the code generator invalidates lowering entries
  but keeps every expansion.
- **Concurrency.** Writers never share a file. New segments appear only by rename. Readers list the
  directory at process start, and the daemon lists it again at the start of each build.
- **Compaction.** At most one compactor runs, holding an OS lock on `compact.lock`. It writes a base
  segment containing the live entries (those reachable from session records seen in the last 14
  days), whose header lists the IDs of the segments it supersedes, and renames it into place.
  Readers ignore superseded segments as soon as they see the base. Writers are never blocked: a
  segment written during compaction is simply not in the superseded list. Superseded files are
  deleted once no process maps them; on Windows a failed delete is retried at the next compaction.
- **Failure.** An empty or fully rejected cache costs one cold build.

### 3.5 Change detection and freshness

- **Input snapshot.** Each build captures, for every input it reads: path, stamp (size, mtime, file
  ID) and the xxh3 of the bytes actually read. The output is exactly the compilation of this
  snapshot (I5); that part holds unconditionally, because the hash is of the compiled bytes.
- **Stamps.** Stamps come from directory enumeration (`FindFirstFileExW` with large fetch on
  Windows). Only files whose stamp changed since the session record are read and hashed. The scan
  also lists file names in every resource search folder (`FILE_DIR`), because a new file there can
  change which resource a reference resolves to (§4.5).
- **Filesystem assumption.** An edit changes a file's size, mtime or file ID. Editors and git
  satisfy this. A file whose mtime falls within 2 s of the scan that recorded it is rehashed on the
  next build regardless (the rule git uses for racy index entries). Writers that bypass metadata,
  such as memory-mapped writes, are outside the assumption.
- **Edits during a build.** Before publishing, the build re-stats every input. If one changed, it
  rebuilds; after two rebuilds it publishes the output for the latest snapshot and reports that
  inputs were still changing. Matching the disk at publish time is best-effort; matching the
  snapshot is exact.
- **Exact mode.** `--exact-inputs` ignores stamps, hashes every source and resource (about 263 MB;
  hypothesized 0.1–0.3 s) and fully hashes any stored pair it reuses. CI, oracle runs and
  reproducibility runs always use it.
- **Watcher.** A filesystem watcher may later narrow the scan. It is only a hint; on overflow or
  error the full scan runs.
- **Removed.** NTFS USN journal proofs, exclusive-handle barriers, persisted input and output
  proofs.

### 3.6 Build integration

- `DQ_COMPILER=native|byond|shadow` stays. `native` calls `dmbc`. An internal compiler error (a
  panic, an unsupported construct) falls back to DreamMaker with a message naming the reason. DM
  source errors never fall back.
- Diagnostics use DreamMaker's format (`file:line:error: message`), so existing tooling and agents
  read them unchanged (§4.9).
- `shadow` runs both compilers and reports per-procedure instruction differences with names
  resolved. It runs nightly.
- Test run slots take the pair ID from `dmbc` and acquire the pair from the store (§4.8) instead of
  copying 270 MB per test world.
- Generated sources (`analyze gen`) remain a separate step for now.

### 3.7 Observability

- Every build appends one JSON line to the session log: wall time per stage, items reused and
  recomputed per memo, reads checked per domain, records validated, resident memory, bytes written,
  cancellations, queue and lock waits, evictions.
- `dmbc explain /obj/item/proc/attack` prints why an item was recomputed: the key change, or the
  recorded read whose answer changed, with its domain and the old and new answers.
- `dmbc stats` prints memo sizes, hit rates, pinned versus evictable bytes, segment counts and pair
  store use per drive.
- Debug tracing stays in, behind `DMBD_TRACE=stage,memo,link,cache,publish`, per the project's
  logging policy (never remove existing debug tracing without permission).

### 3.8 Crate boundaries and the analysis model

The reusable analysis model is part of the initial crate layout, not a later extraction.

| Crate | Holds | May depend on |
| --- | --- | --- |
| `dm-syntax` | Tokens, spans, syntax trees | nothing compiler-specific |
| `dm-preprocess` | Include regions, macro state, expansion, provenance | `dm-syntax` |
| `dm-tree` | The semantic tree (declarations, inheritance, overrides, constants, settings), the occurrence table, the `Resolver` implementation and the read-only query API | `dm-syntax`, `dm-preprocess` |
| `dm-lower` | Lowering to symbolic code | `dm-syntax` and the `Resolver` trait only |
| `dm-link` | ID assignment, relocation, header flags | `dm-tree`, `dm-lower` output types |
| `dm-cache` | Segments, validation, compaction | data types only |
| `dmbd` / `dmbc` | Sessions, locks, scheduling, publication | everything above |
| `dm-analysis` | The analysis export | `dm-tree` read-only API |

- Phase 1 delivers these boundaries with provenance and resolved declarations in place.
- Phase 2 (the daemon) adds a read-only query API over a session's trees: declarations, overrides, occurrences,
  provenance, and the references lowering recorded.
- Hosting lints and generators in the daemon stays in Phase 6.
- `dm-lower` must not depend on `dm-tree`; it sees only the `Resolver` trait. A lint enforces this.

---

## 4. The incremental algorithm

### 4.1 The include-region representation

A file is not an independent expansion unit. An `#include` can appear mid-file, and an included
child can redefine macros its parent uses later. The `.dme` itself and `southern_cross.dm`, which
includes `.dmm` files, both do this.

- The directive pass flattens the include tree into an ordered list of items. A **text item** is an
  include region: a maximal run of one DM file's text between `#include` directives (or the file's
  start and end). An include in the middle of a file splits it into two regions, with the child's
  items between them.
- **Non-text items** are includes that are not DM text: `.dmm` maps (handled by the map memo),
  `.dmf` interface files (resources), and any other kinds DreamMaker accepts. Each keeps its
  position in the order; none is expanded as text.
- Each item knows its file, byte range, include chain and position in the order.
- Repeated includes, conditional includes, includes that land inside an expression or a
  declaration, `FILE_DIR` semantics and path normalization are part of this representation. Each
  follows DreamMaker's observed behavior and gets a fixture before incremental code depends on it.
- `PREPROCESS.md` (written in Phase 0) specifies the representation exactly, with those fixtures.

### 4.2 Region expansion

- A region's expansion records its **effects** (the ordered `#define` and `#undef` operations,
  including `FILE_DIR` changes) and its **incoming reads**. Incoming reads are lookups of names
  the region had not itself defined or undefined at that point: positive and negative macro
  lookups, `#ifdef`, `#ifndef` and `defined()` tests, and uses of `__FILE__` and `__LINE__` (which
  read the region's file and start line).
- Lookups of names the region itself defined or undefined earlier are **internal**. They are
  determined by the region's own text and are not compared against the incoming state.
- Memo key: xxh3 of the region's bytes and the preprocessor version. A region that never reads
  `__FILE__` or `__LINE__` is position-independent: its tokens, fragments and diagnostics are
  shared wherever its bytes recur, and absolute locations come from the current occurrence table.
- Macro state is a persistent hash map, so the state entering each region is a cheap shared
  version.
- **Incremental walk.** S1 walks the items in order. A region is expanded again when its bytes
  changed or any incoming read gives a different answer against the current incoming state.
  Otherwise its recorded effects are replayed onto the state.
- **Δ filter (daemon only).** When the item list is unchanged and the session holds the previous
  build's per-region states, a set Δ of names whose state differs from the previous build at the
  same point filters which regions need checking. Otherwise (a changed item list, or any no-daemon
  build) every region checks all its incoming reads (hypothesized ~40 ms on 8 cores).
- **Parallel checks.** Reads are checked in parallel against states produced by replaying recorded
  effects speculatively. The first region that fails is expanded again, and checking resumes from
  there.
- **Cold build.** Lex all files in parallel, run the directive pass to build the item list and each
  region's incoming state, then expand regions in parallel.

### 4.3 Parsing

- Expanded tokens are split into top-level declaration chunks. Chunks wholly inside one region are
  parsed with the region, and their declaration fragments are stored in its expansion memo entry.
- Chunks that cross a region boundary (an include inside an expression or declaration) are parsed
  from the joined token stream on every build. They are rare, and the fixtures cover them.
- **Skeleton.** Each fragment carries a skeleton hash. It covers declaration headers, var
  declarations with their default expressions, and procedure **metadata `set` statements**. It
  excludes executable body statements and all absolute positions.
- **Metadata `set` statements** are those DreamMaker records in the procedure table rather than in
  bytecode: `name`, `desc`, `category`, `hidden`, `popup_menu`, `instant`, `invisibility`, `src`,
  `background`, `waitfor`, and any others the fixtures show. The parser lifts them into the
  fragment. `LINK.md` lists them, verified against DreamMaker output.

### 4.4 The semantic tree and the occurrence table

The object tree is split into a part that can be reused across builds and a part that is
rebuilt every build.

- **Semantic tree:** types, vars, procs, inheritance, override chains, signatures, flags,
  metadata settings and constant values. It has no absolute positions and no references into
  token buffers.
- **Procedure settings:** `set` statements are proc-wide lexical declarations in encounter
  order, including declarations nested under runtime `if`, loops or `spawn`. Runtime
  ancestors do not guard ABI metadata; later assignments overwrite earlier assignments.
  Removing setting leaves preserves executable containers and condition evaluation.
  Direct evidence: pinned BYOND proc38151 `/obj/item/beacon_locator/process` has flags
  `0x180`, including background `0x100`, despite its setting being inside runtime guards
  and `spawn`. OpenDream's [block compiler](https://github.com/OpenDreamProject/OpenDream/blob/master/DMCompiler/DM/Builders/DMProcBuilder.cs)
  also explicitly treats settings as unconditional to their block.
- **Reuse condition:** the semantic tree is reused when the ordered sequence of declaration
  skeletons is unchanged. Order is part of the condition because override order and redefinitions
  depend on it: moving an unchanged file in the `.dme` changes the sequence without changing any
  hash.
- **Rebuild:** otherwise it is rebuilt from all fragments in order. Rebuilding handles
  `parent_type` changes, override order and redefinitions by construction. A rebuilt tree computes
  a meaning hash for everything lowering can ask about.
- **Occurrence table:** for every declaration occurrence in order, its region, offset, absolute
  file and line, include chain and a reference to its body tokens in the current expansion results.
  It is rebuilt every build (hypothesized ~20 ms). It supplies lowering's inputs, the linker's base
  lines, diagnostics' locations and the analysis API's provenance.

### 4.5 Lowering with complete keys and domain-checked reads

- `lower(occurrence, owner, resolver)` is a pure function. `occurrence` is the procedure's full
  source occurrence; `resolver` is the only way to see the rest of the program.
- **Memo key** (exact, never partial): xxh3 of
  - the declaration header: proc or verb, name, parameter names, defaults, `as` types and `in` lists;
  - the body tokens with relative positions, including `set` statements and local declarations;
  - the owner type path;
  - the lowering stage version;
  - emission flags such as `DEBUG`.
- **Recorded reads**: every `Resolver` call, recorded by a wrapper lowering cannot bypass, as
  `(domain, query, answer hash)`.
- **Domains.** Each read belongs to exactly one domain, and each domain has a version computed every
  build:

  | Domain | Queries | Version covers |
  | --- | --- | --- |
  | Tree | type exists; parent chain; override chain position; var and proc lookup on a type; proc signature; global var and proc lookup; constant value | Identity of the semantic tree (the ordered skeleton sequence) |
  | Resource search | resource path resolution, including negative results (not in folder A, found in folder B) | The `FILE_DIR` list and the file names in those folders, from S0 |

  Builtin entries are fixed per compiler version, which is already in the key.
- **Mandatory reads**, recorded for every procedure whether or not lowering asks: the owner's
  ancestry, and the occurrence's position in its override chain (whether it defines or overrides,
  and what `..()` reaches).
- Answers are hashed by meaning (owner, flags, signature, constant value, resolved file content ID),
  never by table ID.
- **Reuse:** a variant is valid when its key matches and, for every domain whose version changed
  since the variant was last checked in this session, every read in that domain gives the same
  answer. A fresh session treats every domain as changed. Hypothesized cost when the tree domain
  changes: about 2 million lookups, about 50 ms on 8 cores.
- **Initializers** use the same mechanism. The key is the initializer expression tokens, the full
  var declaration occurrence (name, type, flags) and the owner path. A const var used in a proc is a
  constant-value read, so changing the const lowers exactly its users again.
- The edit corpus (§5.2) includes renaming a parameter with an unchanged body, and adding a file
  that shadows a resource in an earlier search folder.

### 4.6 Maps and resources

- `.dmm` files are parsed once per content hash (map memo). Cells and var edits are resolved with
  reads recorded in the same domains, so a map is re-resolved only when one of its reads changed.
- The resource set is the union of resource references in lowered code, initializers and maps.
  Each file's content ID (NQCRC) is cached by stamp. The RSC is rebuilt when the set or a
  resource's content changes, in the order `LINK.md` specifies.

### 4.7 Link and encode

- **Observable orders match DreamMaker.** Several orders are visible to the game: `typesof()`
  results, the order of a datum's `vars` list, verb lists, global and static initialization order,
  and resource alias order (FORMAT.md). `LINK.md` lists every order the game can observe and
  specifies DreamMaker's rule for each, verified by order fixtures (§5.2). The incremental-versus-
  cold oracle cannot catch a wrong choice here, because both sides would agree.
- **Everything else is canonical.** Orders the game cannot observe are fixed by `LINK.md` and depend
  only on the program, never on scheduling, edit history or worker count. No table, including
  strings and lists, ever uses history-dependent IDs.
- The linker assigns table IDs, then copies each procedure's words and patches its relocations in
  parallel, taking base lines from the occurrence table. Header flags, world settings, procedure
  metadata and the procedure reference table are derived from the semantic tree every time.
- Encoding builds the whole DMB in memory, string obfuscation included, and hashes it there
  (hypothesized ~5 ms).

### 4.8 Publishing output pairs

Replacing two files is never atomic, and a DMB that references resource content IDs missing from
its RSC is broken. So the unit of publication is the pair.

- **Pair identity.** A build produces a DMB and an RSC that reference the same resource content
  IDs. The pair ID is xxh3 of both; the DMB hash comes from memory, and the RSC hash from building
  or reusing it.
- **One store per drive.** Hardlinks cannot cross drives, so each drive that holds worktrees has its
  own pair store: `%LOCALAPPDATA%\dmbd\pairs\` on the system drive, `<drive>:\.dmbd\pairs\` on
  others (configurable). A build publishes into the store on its worktree's drive.
- **Publishing.** The pair is written into a temporary directory with a small manifest (sizes,
  hashes), its files are marked read-only, and the directory is renamed into place. Once named, a
  pair directory never changes. RSC files with the same hash are hardlinked between pairs inside the
  store.
- **Acquisition.** Run slots and `dq_focused_test.sh` take a pair ID and acquire it: under a short
  OS lock on the store, they check the pair exists and hardlink its files into the run slot, or copy
  them when the run slot is on another drive. A running world then holds its own links or copies.
  Deleting the store directory never affects it, so running worlds need no tracking.
- **Eviction.** Under the same lock, the evictor deletes pairs not named by any session record's
  last three publications and older than 7 days.
- **Conventional paths.** The worktree's `deepquarry.dmb` and `deepquarry.rsc` are ordinary copies,
  never hardlinks, so nothing that writes to them (a DreamMaker build, for example) can reach the
  store. They are updated RSC first, then DMB, then `deepquarry.pair`, which names the pair ID. Files
  that don't match `deepquarry.pair` are stale, and the next build repairs them. Only the DMB is
  copied when the RSC is unchanged.
- **Verification.** Within one boot, a stored pair is trusted when its files' stamps match the
  manifest. The first use of a pair after a boot hashes it fully (hypothesized under 0.1 s for
  267 MB), because only an OS crash or power loss can lose written data, and the cache never
  fsyncs. Exact mode always hashes. A mismatch deletes the pair, which is rebuilt.
- **Failed builds** publish nothing. The previous pair, the conventional paths and
  `deepquarry.pair` stay as they were, and `dmbc` exits non-zero without a pair ID.
- **Locked outputs.** If a running DreamDaemon locks a conventional path, the build reports it and
  leaves that path for the next build. Run slots are unaffected.
- **Write access.** Store files are read-only, and read-only is a property of the file, shared by
  every hardlink. Phase 0 confirms that DreamDaemon never opens the `.dmb` or `.rsc` for writing
  (dynamic resources go to `.dyn.rsc`). If it does, run slots copy instead of linking.

`PUBLISH.md` (Phase 0) specifies the protocol, its locks and its crash cases.

### 4.9 Diagnostics

- Every memo entry stores the diagnostics produced while computing it, with positions relative to
  its own unit.
- Every build reports the complete diagnostic set: diagnostics replayed from reused memo entries
  plus those from items computed in this build. Each is mapped to file and line through the current
  occurrence table and provenance, and the set is reported in source order. An error therefore
  appears on every build until it is fixed, never only on the build that first computed it.
- Memo entries computed during a failed build are still appended to the cache, so fixing the error
  is fast.
- The oracle compares the diagnostic output too (I4).

---

## 5. Correctness contracts

### 5.1 Invariants

| Invariant | Statement | Enforced by |
| --- | --- | --- |
| I1 Purity | Expansion, parsing, lowering and map resolution depend only on their keys and recorded reads. | Crate boundaries; the `Resolver` trait is lowering's only access to program state; a lint bans globals and statics in those crates. |
| I2 Complete inputs | Everything a memoized result depends on is in its key or is a recorded read. For lowering, the full procedure occurrence is in the key. For expansion, every read of incoming state and position is recorded. Every read is tagged with its domain and rechecked whenever that domain's version changes. | Verify mode; the edit corpus. |
| I3 Determinism | Output bytes depend only on the input snapshot and the compiler, on any OS. | `LINK.md` orders; canonical paths; tests with 1, 2 and 16 workers and a shuffled scheduler. |
| I4 Oracle | An incremental build equals a cold build of the same captured snapshot: DMB, RSC and diagnostics. A comparison whose inputs moved is invalid, not failed. | Oracle checks on every benchmark and in CI (§5.2). |
| I5 Snapshot | Published output is exactly the compilation of the captured input snapshot. Under the filesystem assumption (§3.5), a file edited during a build is detected and the build repeated. | Hashing the bytes compiled; re-stat before publish; `--exact-inputs` in CI. |
| I6 Pairs | Nothing that starts a world can use a DMB and an RSC from different pairs, and eviction never removes a pair during acquisition. | Immutable pair directories; acquisition and eviction under one store lock; `deepquarry.pair`. |
| I7 Parity | Every behavioral difference from DreamMaker output, including any order the game can observe, is on the divergence list with an explanation. | The frozen baseline (§5.3), order fixtures and nightly parity runs. |
| I8 Diagnostics | Every build reports the complete diagnostic set at current locations, and a build with errors publishes nothing. | Replay from memo entries; the oracle compares diagnostics; the edit corpus. |
| I9 Serialization | Two builds of one session never run at once, and publication is never interrupted. | The session lock; non-cancellable publication. |

### 5.2 Checks

| Check | Catches | When |
| --- | --- | --- |
| `cargo test` with fixture compiles | Regressions inside each crate | Every commit |
| Verify mode (`DMBD_VERIFY=1`) | Missing reads (I2). Recomputes a random 5% of memo hits (all of them in CI) and compares. | CI, benchmark harness, nightly |
| Oracle | Any incremental bug (I4). The oracle receives the incremental build's snapshot manifest (paths and hashes), checks every input against it, runs a cold build in a fresh process with an empty cache and its own pair store, checks the inputs again, and compares DMB, RSC and diagnostics byte for byte. If inputs moved, the comparison is marked invalid and retried. | Every benchmark run; CI on the edit corpus |
| Edit corpus | Known-risky edits, each applied and reverted: body; new var; new proc; changed default; parameter renamed with an unchanged body; `set category` changed in a verb; widely used `#define`; `#ifdef` toggle; macro redefined by a child include and used later in the parent; include moved within the `.dme`; include inside an expression; `FILE_DIR` change; a new file shadowing a resource in an earlier search folder; lines inserted above a procedure; an error introduced and built twice (reported both times), then fixed; new icon; map edit; type rename. | CI |
| Order fixtures | Wrong observable orders (I7). For each order in `LINK.md`, a small world prints it; native and DreamMaker output must print the same. | CI |
| Cache contract tests | Truncated segment; corrupted record (checksum and bytecheck); two concurrent writers; compaction during writes and reads; a rejected segment leaves no dangling references. | CI |
| Pair contract tests | Process killed between RSC and DMB updates; run slots still see one consistent pair; eviction racing an acquisition; cross-drive copy fallback; conventional paths repaired on the next build; a modified store file is detected; first use after a new boot hashes the pair. | CI |
| Session lock test | Two concurrent no-daemon builds of one worktree, and a no-daemon build racing a daemon build, publish one after the other. | CI |
| History replay | Real edit mixes. Replays the last 300 master commits through one session, with the oracle after each. | Nightly |
| Fuzzer | Rare interactions. Random token and declaration mutations of real files, with the oracle after each. | Nightly, time-boxed |
| Game parity | Behavior (I7). Full unit-test suite on native and DreamMaker builds of the same commit, compared per test through normalized error identities (§5.3). | Nightly |
| Instruction diff | Codegen drift. Per-procedure diff against DreamMaker output with names resolved. | Nightly, on demand |
| Diagnostic parity | Missed or spurious compile errors. A corpus of broken snippets: native errors must cover DreamMaker's. | CI |

### 5.3 The parity baseline

Phase 0 freezes the comparison that already exists in `FULL_SUITE_COMPARISON.md`:

- **Inputs:** source snapshot ID and the private compatibility edits both compilers used; both
  compiler binaries (DreamMaker version, native binary hash); runtime configuration (memory and
  time limits, map-template substitutions, Verdigris build); fixed random seeds and configuration
  wherever the game allows them.
- **Raw records:** per-test status, complete failure messages and runtime error records, kept
  unmodified.
- **Normalized identities:** comparisons use a normalized identity for each error: its message
  with values, references and timestamps stripped, plus the procedure and source line. Counts per
  identity are compared, not raw text.
- **Nondeterminism policy:** each output is run three times. An identity whose presence or count
  varies between runs of the *same* output is classified as nondeterministic. It is tracked
  separately and does not count as a divergence unless its distribution differs between compilers.
- **The divergence list:** the native-only failure, the five shared failures whose details differ,
  and the deterministic runtime-error differences, including errors recorded in passing tests.

**Parity means:** no new divergence appears against this baseline, and every existing divergence
has an explanation: a root cause, or a recorded decision that the difference is acceptable. A higher
pass count alone is not progress. Byte equality stays strict for the native incremental-versus-cold
oracle; normalization applies only to runtime comparisons with DreamMaker.

> **Measurement rule.** A performance number from a build that has not passed the oracle does not
> count.

---

## 6. Performance framework

The targets are acceptance criteria. All reported times are end to end: they include cache
validation, pair hashing, store writes and worktree copies wherever a build does them. The first
measurements (§6.0) showed the stage hypotheses in r4 were 10–50× too optimistic for the stages
that rerun on every build. The incremental targets now depend on the stage budgets in §6.0, not
on more caching.

### 6.0 Measured so far, and binding stage budgets

Measurements from 7 October: 2 workers, a contended machine (7–21 competing Cargo/rustc
processes), warm OS file cache. They are a direction, not acceptance numbers.

| Build | Result |
| --- | --- |
| Phase 1 cold, test defines (probe 40) | 33.1 s, 3.25 GB peak private memory |
| Phase 1 cold, server defines | 35.0 s |
| Phase 2 cohorts G–K, populate cache | 79–197 s |
| Phase 2 cohorts G–K, unchanged | 3.4–4.4 s |
| Phase 2 cohorts G–K, body edit | 64–110 s (one procedure recompiled) |
| Phase 2 cohorts G–K, cold | 56–83 s |

Cohort F body edit by stage: frontend 13.5 s, resources and maps 6.9 s, ABI 4.8 s, initializers
4.2 s, lowering 13.2 s (one miss), link 8.1 s, composition 2.8 s, publication 4.4 s.

Binding cold budgets per stage, at 8 workers, judged by CPU time as defined in §6.5. A stage over
budget is Phase 1 work, never a reason to add a cache. "Critical path" is the slowest thread's CPU
time in the stage; "total" is the CPU time of all threads together. The measured column is wall
time from the contended runs and is shown for direction only.

| Stage | Critical-path CPU | Total CPU | Latest measured (wall, 2 workers, contended) |
| --- | ---: | ---: | ---: |
| Input scan and hashing | ≤ 0.5 s | ≤ 1 s | not separately measured |
| Frontend: directives, expansion, parse | ≤ 3 s | ≤ 12 s | 7.4–21.9 s |
| Semantic tree and occurrence table | ≤ 1 s | ≤ 2 s | not separately measured |
| Resources and maps, cold hashing | ≤ 2 s | ≤ 6 s | 4.7–15.3 s |
| ABI preparation and initializers | ≤ 1.5 s | ≤ 4 s | 5–9 s |
| Lowering, all bodies | ≤ 3 s | ≤ 16 s | 6.3 s |
| Link | ≤ 1 s | ≤ 2 s | 4.7–9.2 s |
| Composition, encode, publication | ≤ 1.5 s | ≤ 3 s | 7–19 s |
| **Total cold** | **≤ 15 s** | **≤ 40 s** | **33 s** |
| **Peak private memory** | | | **3.0–3.5 GB; budget ≤ 1.5 GB** |

I/O budgets per build, since CPU time does not include waiting on the disk:

| Build | Read | Written |
| --- | ---: | ---: |
| Cold, empty cache | ≤ 400 MB plus cache population | ≤ 600 MB plus cache segments |
| Body edit (RSC unchanged) | ≤ 50 MB | ≤ 120 MB |
| Unchanged | ≤ 5 MB | ≤ 1 MB |

When a stage reruns in an incremental build, its incremental cost may not exceed its cold budget
(the whole-program stages: input, tree and occurrences, link, composition and publication).
Memoized stages (expansion, lowering, maps) must cost at most one tenth of their cold budget on a
full hit.

### 6.1 Targets (daemon running)

| Scenario | Target | Hypothesis | Expected to be dominated by |
| --- | ---: | ---: | --- |
| Unchanged | ≤ 100 ms | 50–70 ms | Input scan, pair stamp check |
| Procedure body edit | ≤ 1 s | 0.35–0.65 s | Link, encode, store write and worktree copy |
| New var or proc, changed default | ≤ 2.5 s | 0.85–1.6 s | Tree rebuild, read checks, link |
| `#define` used in ~500 files | ≤ 6 s | 2–4 s | Expansion and lowering again |
| Map edit | ≤ 2 s | 0.5–1.5 s | Map parse and cell resolution |
| New or changed icon | ≤ 2 s | 0.8–1.5 s | Building the 218 MB RSC and copying it to the worktree |
| Cold build, empty cache | ≤ 20 s | 10–15 s | Lowering and resource hashing |
| Six worktrees editing at once | ≤ 1.5 s each | about 1 s | Shared worker pool, 3-build limit |

Each target is a critical-path CPU figure (§6.5): the time the build would take on an otherwise
idle machine with enough cores. Total CPU and I/O are reported beside it. Total CPU budgets: body
edit ≤ 2 s, new var or proc ≤ 5 s, unchanged ≤ 0.2 s. If these hold, the compiler stops being the
slow part of the edit loop: a focused test spends about 25 s booting the world after the compile.

### 6.2 Without a daemon

A one-shot build with a warm cache does everything a daemon build does, plus starting up, mapping
the cache, validating the records it uses, checking every region's macro reads, rebuilding the
semantic tree, and checking every recorded read against it.

| Body edit, no daemon (hypothesis) | Time |
| --- | ---: |
| Start the process, map the cache, build lookup indexes | 50–100 ms |
| Validate the records used (checksum and bytecheck; link touches every lowering record) | 50–100 ms |
| Scan inputs and compare with the worktree's session record | 50–100 ms |
| Check every region's incoming macro reads | ≈ 40 ms |
| Expand the changed region, rebuild the occurrence table | 30–60 ms |
| Rebuild the semantic tree | 300–500 ms |
| Check all recorded reads against it | ≈ 50 ms |
| Link, encode, hash, store write, worktree copy | 400–450 ms |
| Append the new cache segment | 5–20 ms |
| **Total** | **0.98–1.42 s** |

| Scenario | Daemon | No daemon, warm cache |
| --- | ---: | ---: |
| Unchanged | 50–70 ms | 120–220 ms |
| Body edit | 0.35–0.65 s | 0.98–1.42 s |
| New var or proc | 0.85–1.6 s | 1.2–1.9 s |
| First build after a reboot | add pair hashing (~0.1 s) | add 0.3–0.6 s to read the cache, plus pair hashing |

This table is a hypothesis that assumes the §6.0 budgets are met. Measured no-daemon body edits
were 64–110 s because the whole-program stages had not been made fast. The no-daemon body edit can
only approach 1.5 s once the frontend, tree, link, composition and publication fit their budgets;
until then, the daemon (new Phase 2) is the route to fast edits.

### 6.3 The slowest changes

Speed depends on what an edit invalidates, not on its size. Hypotheses for the daemon; add about
0.6 s without one.

| Change | What reruns | Hypothesis |
| --- | --- | ---: |
| Empty cache, or the preprocessor changed | Everything | 10–15 s |
| Code generator changed | Lowering of all 65,000 procedures; every expansion is reused | 3–8 s |
| A macro used nearly everywhere expands differently | Most regions expanded again, most procedures lowered again | 3–5 s |
| `SECONDS` changes meaning | Regions with its 3,200 uses (1,155 files) expanded again, the procedures containing it lowered again, tree rebuilt | 1.5–2.5 s |
| Same macro reformatted, same expansion | Those regions expanded again; occurrences hash the same, so no lowering | 0.5–1 s |
| The `.dme` include order changes | Regions after the move check their reads; tree rebuilt for override order | 1–3 s |
| New var or proc signature on `/datum` or `/atom` | Tree rebuild, all tree-domain reads checked, procedures that resolved that name lowered again | 1–2 s |
| A file added to a resource search folder | Resource-domain reads checked; procedures whose resolution changed lowered again | 0.4–0.8 s |
| Pull or rebase touching N files | Proportional to N and to the procedures they change | 0.5 s + 2–5 ms per file |
| Any icon edit | The 218 MB RSC rebuilt, a new pair published, the RSC copied to the worktree | 0.8–1.5 s |
| Edit to `southern_cross-1.dmm` (3.3 MB) | That map parsed again and its cells resolved | 0.3–0.8 s |
| The 1.1 MB generated `declare.dm` regenerated | One large file expanded and parsed again; mostly unchanged occurrences | +20–40 ms |

Each of these costs DreamMaker the same 2 min 11 s as a one-character edit.

### 6.4 Finer-grained options

Each option is added only when a profile of the real edit loop asks for it, and none may make
output depend on edit history.

| Option | Saves (hypothesis) | Cost or risk |
| --- | --- | --- |
| Filesystem watcher for the input scan | 40–50 ms on every build | Missed events; the full scan stays as the fallback. |
| Index from names to the procedures that read them | About 50 ms on structural edits | Low. Checking every read stays as the verify-mode reference. |
| Incremental semantic tree: recompute only changed types and their subtrees | 250–450 ms on structural edits to leaf types; nothing at `/atom` level | Medium. Inheritance flattening must be exact; the oracle covers it. |
| Session tree kept in the cache for no-daemon builds | 300–500 ms per no-daemon build | 50–80 MB written after each structural build. |
| Skip the worktree copy for callers that only use pair IDs | About 40 ms per build | Conventional paths go stale until a build that copies. |

With the first three, the hypothesis is about 0.45 s for a body edit in the daemon (link, encode
and publication remain by design) and 0.35–0.65 s for a structural edit. History-dependent string
and list IDs and append-mode RSC would save more, but they make output depend on edit history and
are rejected (D10).

### 6.5 Measurement rules

- **Baseline first.** The Phase 0 close-out traces the current compiler on the frozen inputs.
  Each stage is then measured separately on the same inputs, and every scenario is also reported
  end to end.
- **Release profile.** Every measured build uses `lto = "thin"`, `debug = "line-tables-only"`,
  `codegen-units = 16`. Development builds use incremental compilation. No per-package `opt-level`
  overrides.
- **Fast rebuilds.** Crates are split so that a change to lowering rebuilds in under a minute.
- **Harness.** `dmb-bench` drives scripted edits on the real project and appends JSON lines to
  `bench/results.jsonl`: commit, scenario, end-to-end time, time per stage (validation and
  publication included), resident memory, memo statistics.
- **Watchdog.** Each run executes under an external watchdog (default 10 minutes). A run that hits
  it is recorded as a failed measurement, never as a timing. Nothing inside the compiler changes
  behavior because of the watchdog.
- **Profiler without elevation.** Every stage and its main sub-stages carry `tracing` spans with
  per-thread CPU time. `--trace <file>` writes a Chrome trace (viewable in Perfetto) and a
  folded-stack flamegraph from the same spans. A counting allocator behind a feature flag reports
  allocations and peak memory per stage. This is the profiler (decided 7 October); samply and
  other tools that need elevation are not used.
- **Profile-backed changes.** A performance commit cites the trace that motivated it and its before
  and after rows. Stage timers alone do not justify a change.
- **Acceptance is judged by CPU time** (decided 7 October). The machine is shared with other
  agents' builds, a game and DreamDaemon, so wall time cannot be controlled. Each run reports:
  - **Critical-path CPU:** for each stage, the largest CPU time of any single thread that worked
    on it, summed over the stages in pipeline order (overlapping stages count once, along the
    longest chain the trace shows). This approximates wall time on an idle machine with enough
    cores, and it is the figure compared with every time target and budget.
  - **Total CPU:** CPU time summed over all threads, compared with the total-CPU budgets. It catches
    wasted parallel work.
  - **I/O:** bytes read and written per stage, and time blocked on I/O, compared with the I/O
    budgets (§6.0), because CPU time does not include disk waits.
  - **Context:** wall time, peak private memory and the count of competing processes. Wall time is
    recorded for information only.
- **Thread CPU precision.** On Windows, `GetThreadTimes` advances in 15.625 ms ticks.
  Spans retain absolute raw `QueryThreadCycleTime` intervals per thread until finalization,
  then integrate overlaps with that thread's naturally observed paired-clock windows of
  at least 500 ms CPU. Two independent windows are required. Rates are local to each window:
  a varying frequency is never converted using one global or envelope rate. Short tails
  outside calibrated windows retain unknown precise CPU; no rate is extrapolated.
  Missing or backwards clocks remain unknown. Changes inside a calibration window remain
  a precision limitation. Linux uses native `CLOCK_THREAD_CPUTIME_ID` nanoseconds.
- **Explicit CPU uncertainty bounds (human-approved).** Successfully paired monotonic
  `GetThreadTimes` boundaries may provide a short-interval lower/upper CPU bound using
  the observed duration plus/minus two coarse ticks (31.25 ms). Negative lower endpoints
  clamp to zero. Bounds require actual clock samples; a missing clock never becomes zero.
  Sum bounds for disjoint contributions, take per-thread maxima for stage critical bounds,
  and sum only the declared sequential stage bounds for pipeline critical CPU. Merge only
  exactly contiguous observed intervals; do not fill missing work. Many tiny intervals may
  produce bounds too wide for acceptance, which is a measurement failure, not permission
  to choose a midpoint. Precise scalar CPU remains unavailable when conversion is incomplete.
  Acceptance requires every relevant upper bound to meet its budget and the **entire**
  covered-thread/process-CPU ratio interval to lie within the unchanged 5% crosscheck
  tolerance. No process-total scaling, guessed cycle rate or tolerance relaxation is allowed.
- **Contention bias.** Shared caches and hyperthread siblings inflate CPU time somewhat on a busy
  machine. A result within 10% over its budget is rerun; it fails if the median of three is still
  over. Nothing is ever stopped to make a run quieter.
- **Workers.** Acceptance runs use 8 workers (the physical core count) and report the median of
  three runs. Runs at 2 workers continue as a regression series only.
- **Cache drive.** Benchmarks use the E: cache (§3.4) or an explicit `DMB_CACHE_DIR`, and check free
  space before populating.
- **Gate.** A CI performance gate on a fixed corpus fails when a scenario exceeds its target or
  regresses more than 20% from the trailing median.

---

## 7. How each failure is prevented

| Failure on the current branch | Root cause | What prevents it here |
| --- | --- | --- |
| No full build finishes in 20 minutes | Intermediate state streamed through a per-record store | State is worked on in memory; no store is read per item on the build path. |
| 146 GB read and 93 GB written per run | Per-record durable transactions, checkpoints, freed-page churn | A build writes one pair (often only a new DMB), one worktree copy and one cache segment. |
| Checking a cached result costs more than recomputing it | Caching at a far finer grain than the work it saves | Three kinds of memo; another needs a profile showing a 10× payoff. |
| Salsa and a custom persistent DAG in conflict | Two incremental engines | One mechanism: memo variants with exact keys and domain-checked reads. No Salsa, no redb. |
| Immutable-node conflicts, selector and ownership bugs | Mutable metadata inside a content-addressed store; leases | Memo values and segments never change; sessions keep mutable state in plain structs; no shared mutable index. |
| 13,409 fallbacks from a 4 MiB workspace | Limits that switch code paths | Limits only evict or queue (§2.5). |
| Each fix uncovers another quadratic | Optimizing from nested stage timers | A sampling profiler is required; stage targets are enforced in CI. |
| 15–30 minutes per data point | `opt-level=1`, single-job builds, deadlines inside the run | Release profile, fast crate rebuilds, a watchdog outside the compiler. |
| Panics found only in benchmarks | A compile check treated as verification; tests not run | `cargo test` and the oracle on every commit. |
| Code too large to reason about | About 150,000 lines, a 681 KB file, 800-character lines | Crate boundaries (§3.8), file size cap, rustfmt, clippy, a fixed glossary. |
| USN journals and exclusive-handle proofs | Trying to prove that disk state is fresh | An exact snapshot contract, a stated filesystem assumption, and an exact mode (§3.5). |
| Output journals, generations, in-place patching | Patching binaries to save emission time | Full link and encode each build, published as immutable pairs (§4.8). |
| 118–133 s of database recovery at startup | A durable database left dirty | Segments are immutable and validated; a bad one is ignored, with no recovery step. |
| Allocation-heavy hot paths | `String` symbol keys, SHA-256 on every item | Hashed symbol IDs, xxh3. |

---

## 8. Engineering rules for the implementing agent

- **Fixed glossary.** Session, Build, InputSnapshot, IncludeRegion, MacroState, ExpansionMemo,
  SemanticTree, OccurrenceTable, Resolver, ReadDomain, ReadSet, LoweringMemo, MapMemo,
  SymbolicCode, LinkedImage, OutputPair, PairStore, CacheSegment, SessionRecord. A new core concept
  needs a change to this design first.
- **Contracts before code.** `PREPROCESS.md`, `LINK.md` and `PUBLISH.md` exist, with fixtures,
  before code depends on them.
- **Documents.** `DESIGN.md` (this file), `STATUS.md` (updated in place: what works, current
  numbers, open issues) and the three contract files. Benchmark results go to `results.jsonl`. No
  dated report files.
- **Code shape.** Files of at most 1,000 lines, rustfmt at default width, clippy with warnings
  denied, and no `#[allow]` without a comment.
- **Commit gate.** Every commit passes `cargo test`, clippy and the fixture oracle. A performance
  commit also includes its profile reference and release-build before and after rows.
- **Profile before caching.** Never add a cache, budget, fallback or retry to fix slowness. Profile
  first and fix the work the profile shows.
- **Limits.** A limit may evict or queue; it may never change the algorithm or the output.
- **Stop-loss.** If a phase misses its exit criteria after two rounds of fixes on the same stage,
  stop and report to the human with the profile.
- **One phase open at a time.** Each phase gets its own branch and merges when its exit criteria
  pass. Code from a frozen phase must keep compiling and passing its tests, but receives no new
  features until its phase reopens.
- **Memo payoff.** A memo kind stays enabled only while a trace shows its full-hit cost at or below
  one tenth of recomputing the same items cold. A memo that fails is disabled, never tuned with
  budgets or admission rules.
- **No admission machinery.** Cache population writes every computed record. Space problems are
  solved by compaction and an explicit cache drive, never by skipping records.

---

## 9. Plan

Durations are rough estimates of focused agent work. Phases run in order; each ends at measurable
exit criteria. Only one phase is open at a time (§8).

### Where things stand (7 October)

- **Phase 0:** mostly done. The contract documents, baseline harness and DreamDaemon write-access
  check exist. Still open:
  - the profile of where cold-build time goes (sampling was stopped at the user's request);
  - reproduction of the frozen baseline.
- **Phase 1 (original):** produced a full, deterministic compile and publication in 33 s at 2
  workers. It did not meet its 30 s target or the parity gate.
- **Phase 2 (original, disk cache):** was started early. Its code works and its incremental output
  is byte-identical to cold output, but body edits take 64–110 s and cold builds regressed to
  56–83 s. It is now frozen (see the review).

The phases below replace the original Phases 1–3. Phases 4–6 are unchanged.

### Phase 0 close-out (≈ 2–3 days)

**Step 0: Freeze and clean up**
- Freeze disk-cache work. The code stays and must keep compiling and passing its tests, but gets no
  new features until Phase 3. Bug fixes needed by the oracle are allowed.
- Remove the tree disk admission (the tree key and payload path) and every byte limit that causes
  a skip rather than an eviction. Output must be unchanged with and without `--no-cache`.
- Fold `archive/PHASE2_PROGRESS.md` into `STATUS.md` (current state only). Move per-cohort numbers into
  `results.jsonl` and the narrative to `archive/`.
- Run the full `cargo test --workspace` once in release mode and record the counts in `STATUS.md`.
  Fix or list every failure.

**Step 1: A profiler that needs no elevation (§6.5)**
- Add `tracing` spans to every stage and main sub-stage, with per-thread CPU time.
- Write the Chrome trace and the flamegraph.
- Add a counting allocator with per-stage peak memory.

**Step 2: Benchmark protocol (§6.5)**
- `dmb-bench` runs at 8 workers, median of three, and reports critical-path CPU, total CPU and I/O
  per stage, with wall time, memory and the competing-process count for context.
- Move the default cache to `E:\.dmbd\cache\` and check free space before population.

**Step 3: Remaining Phase 0 evidence**
- Reproduce the frozen baseline under normalized comparison (§5.3).

Exit criteria:
- The frozen state compiles; the tree-on-disk and skip-on-limit paths are gone.
- Full `cargo test` results are recorded.
- One cold trace and one body-edit trace of the full project, with per-stage wall time, CPU time,
  allocations and memory, and the ten heaviest spans written up in `STATUS.md`. This replaces the
  deferred "ten sampled frames" gate.
- A CPU-time baseline of the current cold build at 8 workers (critical path, total, I/O) in
  `results.jsonl`.
- The baseline reproduces, with nondeterministic identities classified.

### Phase 1: Stage throughput (≈ 4–7 days)

Work strictly from the traces, one stage at a time, worst first. Each change cites its trace
before and after.

- Bring every stage within its §6.0 budget, and peak memory to 1.5 GB or less.
- Split `dm-codegen-byond/src/simple.rs` (12,028 lines) along the boundaries the traces expose
  while working in it.
- Keep the Phase 1 parity gates: order fixtures match DreamMaker, no new divergence against the
  frozen baseline, `cargo test` green.

Exit criteria:
- Every stage within its §6.0 critical-path and total CPU budgets at 8 workers.
- Cold build ≤ 15 s critical-path CPU and ≤ 40 s total CPU. Up to 20 s critical path is acceptable
  if one stage carries a written, trace-backed reason.
- Cold build within its I/O budget.
- Peak private memory ≤ 1.5 GB.
- Identical bytes across worker counts.
- Order fixtures match DreamMaker, and no new divergence appears against the frozen baseline.
- `cargo test` green.

If a stage misses its budget after two trace-guided rounds, stop and report the trace to the human.

### Phase 2: Daemon with in-memory sessions (≈ 3–5 days)

The daemon keeps everything the whole-program stages need resident between builds:

- expanded regions and fragments;
- the semantic tree and occurrence table;
- lowered symbolic code;
- the previous linked image.

A body edit then costs re-expanding one region, lowering one body, relinking, encoding and
publishing.

The disk cache stays off the hot path in this phase. A new session may read the existing cache to
warm up, or simply cold-build.

Work:
- `dmbd` and `dmbc`; the session lock shared with no-daemon runs.
- The draining version handshake; cancellation before publication; crash recovery; a pipe limited
  to the current user.
- Idle trimming and coarse controls (§2.5); the in-memory Δ filter for regions.
- After the edit targets are met: the read-only query API over a session's trees, with the analysis
  export served from it (D16).

Exit criteria:
- With the daemon, in critical-path CPU (§6.5): body edit ≤ 1 s, new var or proc ≤ 2.5 s,
  unchanged ≤ 100 ms, each within its total CPU and I/O budget. The other §6.1 scenarios are
  measured and reported.
- The oracle (DMB, RSC, diagnostics) is clean on the edit corpus and a 300-commit replay.
- Six worktrees editing at once within target; daemon private memory ≤ 1.5 GB working and
  ≤ 0.25 GB idle.
- Killing the daemon mid-build loses nothing beyond that build; rebuilding the compiler mid-build
  lets other builds finish.
- The analysis export produces the same facts as before, from the API.

### Phase 3: Disk cache and no-daemon mode (≈ 4–6 days)

Resume the frozen cache code under these rules:

- **Zero-copy hits.** Hits are read in place from mapped segments, and only the records used are
  validated.
- **Measured payoff (§8).** Each memo kind must show, in a trace, a full-hit cost at or below one
  tenth of recomputing the same items cold. A memo kind that fails is disabled.
- **No tree on disk** unless a trace shows tree rebuild dominating no-daemon builds after Phase 1.
  Even then, its key is the ordered skeleton hash (§4.4), not the tree's contents.
- **No admission budgets.** Population writes every record.

Exit criteria:
- Without a daemon, in critical-path CPU (§6.5): unchanged ≤ 250 ms, body edit ≤ 1.5 s, new var
  or proc ≤ 2 s.
- Populating the cache costs at most 20% more total CPU than a cold build.
- The oracle is clean on the corpus and the replay with the cache in use.
- Cache, pair and session contract tests pass, including six concurrent one-shot builds and
  compaction under load.

### Phase 4: Build integration (≈ 2–3 days)

Work:
- `build.ts` native mode through `dmbc`, with DreamMaker fallback on internal errors.
- Run slots and `dq_focused_test.sh` acquire pairs by ID; shadow mode nightly.
- The diagnostic parity corpus.

Exit criteria:
- One week of agent worktrees on native with zero oracle mismatches and no new divergences.
- No fallbacks except listed, known ones.

### Phase 5: Hardening (ongoing)

Work: nightly fuzzer and history replay; explain or fix every entry on the divergence list; Linux
build for CI.

Exit criteria: no unexplained divergences remain; native output used for CI test runs.

### Phase 6: Lint and generator hosting (later)

Work: serve `tools/analyze` lints and generators from the daemon's tree API, removing their separate
17 s cold parse.

Exit criteria: lints and generators produce the same results from the API.

From today, Phases 0–4 are roughly three to four weeks of focused agent work. The risk now sits in
Phase 1: the traces have to show where 33 s of cold build goes, and each stage has to come within
its budget.

---

## 10. Risks and open questions

- **The whole-program stages are the main risk.** They measured 10–50× over the r4 hypotheses
  (§6.0), and the incremental targets depend on them coming within budget. Phase 1 attacks them
  with traces before any further caching. If a stage cannot reach its budget, the targets that
  depend on it are revised with the human, not worked around with caches.
- **Measurement noise.** The machine is shared with other agents' builds, a game and DreamDaemon,
  so acceptance uses CPU time (§6.5). Critical-path CPU assumes free cores; on this machine a
  build may still take longer in wall time when other work is running, and that is expected.
- **Lowering speed.** Cold lowering measured 6.3 s at 2 workers; the budget is 3 s at 8 workers.
- **The include-region representation is the most subtle new code.** Phase 0 writes it down with
  fixtures before the incremental walk depends on it, and verify mode samples expansion hits as
  well as lowering hits.
- **Observable orders are a parity risk the main oracle cannot see.** Both incremental and cold
  builds would agree on a wrong order. `LINK.md`, the order fixtures and the parity runs cover it.
- **Canonical order renumbers on most edits.** One added string shifts every later ID, so every
  procedure is repatched on every build. This is deliberate: it keeps output independent of
  history. Its cost (hypothesized ~200 ms) is measured in Phase 1.
- **The no-daemon body edit depends on Phase 1.** It reruns every whole-program stage, so it can
  approach 1.5 s only once those stages fit their budgets. The session tree option (§6.4) is a
  later remedy, used only if a trace shows tree rebuild dominating.
- **Widely used `#define` changes approach a cold build** (2–6 s hypothesized). They are rare.
- **Memory.** Measured at 3.0–3.5 GB per build against a 1.5 GB budget. The counting allocator
  (§6.5) has to show where it goes before the daemon holds six sessions at once.
- **DreamDaemon write access.** If DreamDaemon opens the `.dmb` or `.rsc` for writing, read-only
  hardlinked run slots fail; run slots then copy, as today.
- **Pair store disk use.** Each distinct pair can cost up to 267 MB per drive; RSC sharing by hash
  inside a store and 7-day eviction keep it bounded. Phase 3 measures actual use.
- **Windows will not delete a file another process has mapped.** Compaction supersedes by header
  first and deletes old segments later, retrying until no process holds them.
- **A running DreamDaemon may lock a conventional output path.** Run slots acquire from the pair
  store and are unaffected; the conventional copy waits for the next build.
- **Generated sources sit in the edit loop before the compiler.** Their latency is outside this
  design until Phase 6.
- **The semantic knowledge lives in `bootstrap.rs`.** Extracting it without losing behavior is the
  main Phase 1 effort. The frozen baseline, the order fixtures and the instruction diff guard it.

---

## Appendix A: Decision record

| ID | Decision | Rejected alternative and why |
| --- | --- | --- |
| D1 | Work in memory; a daemon per user keeps it warm, and a no-daemon mode maps the same cache | A disk-backed store read per item: measured two orders of magnitude slower. One daemon per worktree: workable, but less is shared. |
| D2 | Explicit memo variants with exact keys and recorded reads | Salsa: machinery for deep query graphs applied to a two-level problem. It is not persistent, which is what led to bolting redb onto it. The dependency contract (I2) matters more than the engine. |
| D3 | Rerun include order, occurrences, link and encode in full; reuse the semantic tree whole or rebuild it | Fine-grained tracking: more code and risk than it would save. |
| D4 | Relocatable symbolic code and a full link each build | In-place DMB patching: needs journals and layout constraints, and breaks byte-equality with a cold build. |
| D5 | Append-only, self-contained, validated cache segments | A transactional database: recovery time, write amplification, and durability nobody needs for a cache. A single snapshot written when idle: a no-daemon build would have to rewrite all of it. |
| D6 | xxh3-128 for identity | SHA-256: there is no adversary, and it is about an order of magnitude slower. |
| D7 | Exact snapshot contract, stamps with a stated filesystem assumption, an exact mode | USN journal proofs: complex, Windows-only, and still not a guarantee. |
| D8 | The oracle compiles the captured snapshot; parity is a divergence list over normalized identities | Byte-equality with DreamMaker: its internal ordering is undocumented. Pass counts: they hide differing runtime errors. Raw runtime records: they differ between runs of the same output. |
| D9 | Symbol IDs are 64-bit hashes of their text | A sequential interner: separate processes appending to one cache would assign conflicting IDs. |
| D10 | Canonical order for every table the game cannot observe, on every build | Stable string and list IDs, append-mode RSC: faster on some edits, but output would depend on edit history. |
| D11 | Outputs published as immutable pair directories; world starters acquire from them; worktree paths are copies | Renaming RSC then DMB in place: not atomic across two files. Hardlinks into worktree paths: an in-place write there would corrupt the shared store. |
| D12 | Segments discovered by directory listing; compaction supersedes by header under one lock | A shared manifest: concurrent writers and the compactor can lose each other's updates. |
| D13 | The lowering key is the full procedure occurrence; outside context is recorded reads, some mandatory | A body-only key: renaming a parameter with an unchanged body would reuse stale code. |
| D14 | The expansion unit is the include region; reads split into incoming and internal; non-text includes are items | Whole files: an included child can change macros its parent uses later, and reads after an internal `#define` don't depend on incoming state. |
| D15 | Semantic tree reuse requires the same ordered skeleton sequence | A set of skeleton hashes: moving an unchanged file in the `.dme` changes override order without changing any hash. |
| D16 | Analysis boundaries (syntax, provenance, resolved declarations) from Phase 1; query API with the daemon in Phase 2 | Extracting them in Phase 6: it would repeat the `bootstrap.rs` extraction problem. |
| D17 | Coarse limits that only evict or queue; an external benchmark watchdog | Per-component budgets that trigger fallbacks; no limits at all; deadlines inside the compiler. |
| D18 | Reads are tagged by domain (tree, resource search) and rechecked when that domain's version changes | Checking reads only after a tree change: a `FILE_DIR` change or a new file in a search folder would leave stale resource references. |
| D19 | A reusable semantic tree plus an occurrence table rebuilt every build; metadata `set` statements in skeletons | Reusing one combined tree: stale body references, locations and provenance. Excluding all body content from skeletons: verb metadata changes would be missed. |
| D20 | One pair store per drive; hardlinks within a drive, copies across | One store under `%LOCALAPPDATA%`: worktrees on E: could never hardlink. |
| D21 | Observable orders follow DreamMaker, verified by order fixtures | Any canonical order: `typesof()`, `vars` order and initialization order are visible to the game, and the incremental-versus-cold oracle cannot detect a wrong choice. |
| D22 | Stored pairs trusted by stamp within one boot, hashed on first use after a boot and in exact mode | Hashing before every reuse: breaks the unchanged-build target. Never re-hashing: a power loss after rename could leave a torn pair in use. |
| D23 | Diagnostics stored with memo entries and replayed every build; failed builds publish nothing | Reporting only recomputed items: an error would vanish on the next build. |
| D24 | One OS lock per session shared by daemon and no-daemon builds; publication not cancellable; draining version handshake | Queuing inside the daemon only: two one-shot runs could interleave their publication. Killing builds on upgrade: rebuilding the compiler would break other worktrees' builds. |
| D25 | Stage throughput (Phase 1), then the daemon (Phase 2), then the disk cache (Phase 3) | Disk cache before the daemon: a no-daemon build reruns every whole-program stage, so caching cannot reach the targets while those stages are slow (measured: 64–110 s body edits). |
| D26 | `tracing` spans with Chrome-trace and flamegraph output are the profiler; nothing requiring elevation is used (user decision, 7 Oct) | Stage timers alone: they cannot explain where time goes inside a stage. samply: it needs administrator prompts. |
| D27 | Acceptance by CPU time at 8 workers, median of three: critical-path CPU against time targets, total CPU and I/O against their budgets (user decision, 7 Oct) | Wall time on a contended machine: identical scenarios varied 2.5× and could not be attributed. Quiet benchmark windows: not available on a shared machine. |
| D30 | The shared cache defaults to `E:\.dmbd\cache\` (user decision, 7 Oct) | `%LOCALAPPDATA%` on C:: population filled the drive. |
| D28 | A memo kind stays enabled only while its measured full-hit cost is at most one tenth of cold recomputation; hits are read in place | Decoding and copying records on hit: measured 3–44 s to reuse procedures that lower cold in 6.3 s. |
| D29 | No admission budgets or skip-on-limit paths in the cache; no tree persistence without a trace | Admission budgets and a 32 MiB key limit: population lost 31,272 records, and the tree cache silently skipped itself. |
| D31 | 2026-10-12, user decision: Phase 1 is closed. Cold release at 8 workers is about 11 s critical path, 12.5-15 s wall, and 1.55 GB peak against the 1.5 GB budget, accepted as is. Ownership of the compiler moves to Claude. Priorities in order: release-profile measurement, retained memory, incremental short-circuits, cleanup | Holding Phase 1 open for the last 50 MB and 2-4 s: the remaining risk is in retained memory and edit latency, which the phase-2 targets measure. |

## Appendix B: Revision history

- **r1, 6 Oct 2026.** Initial design.
- **r2, 6 Oct 2026.** An append-only mapped cache replaces the idle snapshot; no-daemon mode becomes
  first-class; sections on sharing, idle memory, slowest changes and finer-grained options.
- **r3, 6 Oct 2026.** Astra's first review: baseline claims corrected and parity defined as a
  divergence list; complete lowering keys and mandatory reads; include-region preprocessing; ordered
  tree reuse; the output pair protocol; manifest-free validated segments; a freshness contract the
  mechanism can deliver; hypotheses instead of forecasts; coarse limits and the watchdog;
  history-dependent IDs rejected; analysis boundaries in Phase 1.
- **r4, 6 Oct 2026.** Astra's second review, plus a self-review:
  - Reads checked per domain (§4.5, D18).
  - Semantic tree and occurrence table split; metadata `set` statements in skeletons;
    position-independent memo values with current locations (§3.3, §4.3, §4.4, D19).
  - The oracle compiles the captured snapshot and compares diagnostics (§5.2, I4).
  - Pair acquisition and eviction under one lock; pair stores per drive; verification per boot;
    the DreamDaemon write-access check (§4.8, D20, D22).
  - Observable orders follow DreamMaker; `LINK_ORDER.md` becomes `LINK.md` (§4.7, D21).
  - Diagnostics replayed every build; failed builds publish nothing (§4.9, I8, D23).
  - The session lock, non-cancellable publication, the draining version handshake and a user-only
    pipe (§3.1, I9, D24).
  - Non-text includes and canonical paths (§3.3, §4.1).
  - A normalized baseline with a nondeterminism policy (§5.3).
  - End-to-end budgets including validation and publication (§3.2, §6).
- **r5, 7 Oct 2026.** After the first measurements and `archive/REVIEW_20261007.md`:
  - Measured results and binding per-stage cold budgets (§6.0). The r4 stage hypotheses were
    10–50× too optimistic for the whole-program stages.
  - Memory measured at 3.0–3.5 GB against a 0.45–0.6 GB estimate; budget 1.5 GB (§2.2).
  - A profiler without elevation; acceptance by critical-path CPU, total CPU and I/O at 8 workers;
    the cache on E: (§3.4, §6.5, D26, D27, D30). These three follow the user's decisions of
    7 October.
  - Plan reordered: Phase 0 close-out, stage throughput, the daemon, then the disk cache (§9, D25).
    Disk-cache work is frozen; the analysis API moves with the daemon.
  - The memo payoff rule and no admission machinery (§8, D28, D29).
