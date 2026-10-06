# Output pair publication contract — Phase 0

Status: proposed protocol and authored crash-case fixtures. The functional access
probe has been captured; requested-access tracing is deferred at the user's instruction.
This document supplements DESIGN.md section 4.8. Publisher implementation belongs
to the later implementation phase.

## Authority and identity

A pair is the exact DMB and RSC byte sequences. Its manifest records format version,
individual lengths and xxh3-128 hashes, plus a domain-separated pair hash of the two
length-framed hashes. Filename, mtime or an RSC content ID alone is not pair identity.
The canonical names inside a pair are deepquarry.dmb and deepquarry.rsc.

Choose a configured store on the destination volume. Drive letters alone are not a
volume identity: junctions and mounts may cross volumes. If hardlink creation reports
cross-device or unsupported filesystem, copy without changing the pair identity.
A writable root such as <drive>:\.dmbd is a configurable location, not a permission
assumption. Conventional worktree output paths always receive copies.

## Publication

1. Write both files and manifest in a unique private temporary directory on the
   store volume. Close all write handles. Check actual lengths and hashes.
2. Mark store files read-only. Acquire the store's short OS lock and rename the
   complete directory to its pair ID. An existing ID is validated and reused;
   never replace or modify an existing pair. A corrupt existing pair is quarantined
   under the lock; recovery never mutates a file with existing hardlink readers.
3. Publish the successful session's last-three-pair record under the same lock as
   eviction. The new pair must not become evictable between directory publication
   and this record update. Release the lock after that update.
4. Update conventional copies RSC, then DMB, then a temporary pair marker renamed
   into place. This sequence is not atomic. Markers describe expected bytes;
   mismatches are repaired on the next build. A world starter never trusts these
   paths. Locked conventional copies are reported without claiming they updated.

Publication is not cancellable after step 2 begins. Source-error builds publish
nothing. A crash may interrupt steps; it is not equivalent to a source-error build.
No cache durability guarantee is implied. A power loss can leave named files torn:
first use after a boot and exact mode authenticate both actual files before reuse.
A within-boot validated-pair cache must retain its precise file identity and stamp;
external modifications invalidate it. Session/cache records are hints, not permission
for a starter to skip authentication.

## Acquisition and eviction

Acquire and eviction use the same OS lock. Acquire validates the selected pair,
creates both links or copies in a unique private slot, and exposes a slot-complete
marker only after both files are present and authenticated. On any failure, the
private slot is not runnable. Cross-volume copying stays under the lock so eviction
cannot remove its source midway. Afterwards the slot owns independent links or
copies: deleting store names does not delete its files. Running worlds need no
persistent pin registry. Slot cleanup runs only after its own child process exits.

Eviction, under the lock, rereads the current session records and excludes their
last three pair IDs. Only other pairs older than seven days are candidates. A
concurrent session record update uses this lock too. Read-only file deletion must
not clear attributes on an inode shared with running hardlinks: failed removal is
retained for later, or delete-name permissions are used without mutating shared
attributes. Never recursively delete a guessed directory or a live run slot.

Hardlinks are enabled only when the pinned DreamDaemon probe demonstrates compatible
access. If write access is requested, use writable slot copies; immutable store files
remain read-only. No global compatible-client behavior is changed by this decision.

## Crash cases and acceptance

| Interruption / race | Required outcome |
| --- | --- |
| During temp file writes | Temporary pair ignored; previous published pair usable |
| After final rename before session record | Pair may be orphaned; it cannot be evicted during locked publication |
| During conventional RSC/DMB copies | Marker mismatch detected; starters still use coherent store pair |
| During marker replacement | Old or new marker; contents verified and repaired |
| Duplicate concurrent pair publish | One validated immutable directory; no overwrite |
| Acquire paused after first slot file; eviction competing | Eviction waits; slot exposes nothing until both files exist |
| Pair evicted after acquisition | Existing slot remains byte-identical and runnable |
| Corrupt same-length store file | Authentication rejects before world start; no silent reuse |
| Power loss after rename | First-boot authentication accepts exact bytes or rejects pair |
| Cross-volume slot | Complete copied pair; no partial visible slot |
| Locked conventional output | Clear report; valid pair ID remains usable |

fixtures/phase0/publish/cases.json is the executable-test specification for the later
publisher implementation. Those tests are pending, not simulated by a text manifest.
The Phase 0 access probe is independently runnable; see its README.

## Observed Phase 0 access probe

BYOND console DreamDaemon 516.1687 (file version5.0.516.1687), SHA256
`2E3815875C4DCF3C50DE70C1C6E017849EFE8697C428F02AB9EE77C306C8ABF0`:
writable-copy PID34544 passed; read-only-hardlink PID30680 failed the static
resource check with `BUG: Missing or invalid access_probe.rsc file (0/2 resource
files found)`. The failed child still exited0; completion markers are required.
Both pair hashes remained unchanged. This selects writable copied run slots for
this engine. Requested-access analysis is deferred at the user's request;
runtime failure alone does not identify which open rights caused it. Procmon
capture/export work is stopped; existing evidence is preserved without further
trace inspection.
Evidence receipts are captured in fixtures/phase0/publish/results.json.
