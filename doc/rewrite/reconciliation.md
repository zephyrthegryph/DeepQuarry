# Reconciliation: every open branch, snapshot and worktree against the OM core

Status: **done** on `rewrite/reconcile` (2026-09-27). Rule: our architecture
(object_model_core.md, lifecycle.md, containment.md, life_on_om.md,
migration_plan.md) wins; nothing lands as a parallel system. Each source is
**MERGE** (merged as is, conflicts resolved onto the OM core), **PARTIAL**
(the parts that fit were ported, the rest dropped), **SUPERSEDED** (already
covered by the OM core; record-only merge, strategy `ours`) or **DROP** (not
merged; kept for reference or dead).

Compile baseline stays at the 4 known errors (`dq_rule_test`,
`dq_test_shard_count`); `tools/ci/check_ratchets.sh` passes.

## 1. Triage

| Source | Verdict | What landed / why |
|---|---|---|
| `w5/interact`, `w5/harm`, `w5/mem`, `w5/automation`, `w5/loose`, `w5/balance` (via `w5/integrate`, `w6/integrate`) | MERGE | Combat-mode gates, actor adapters, INJURE_CONTINUOUS, lazy organ lists, treatment-demand automation, fracture/cardiac vitals, balance harness. |
| `w5/status` | PARTIAL | Human sleep/idle rules ported onto OM stages (`e9deb29a1f`). The status-counter conversion (stun/weaken/... as `/datum/status_effect`) is superseded by OM timed contributions; the SSD permanent hold by OM's unattended-body top-up. |
| `w6/k1` (clock core) | SUPERSEDED | `/datum/clock`, provided clocks and `life_wake_in()` are replaced by OM clock domains; `om_clock_now(E, CLOCK_BIO)` added for reading local biological time (`73d368bac6`). |
| `w6/o2` (limb part slots, incl. `rewrite/ledger-joint`) | PARTIAL | The limb tree is keyed part slots declared as OM relation slots (`acdfc05a88`). |
| `w6/o5` (death pipeline) | MERGE | Sealed death pipeline, `return_from_death()`, vital predicates (`a8ddcffeed`); `delete_on_death` runs from the pipeline's final hook (lifecycle verbs, test `dq_vital_delete_on_death`). |
| `w6/integrate` remainder | SUPERSEDED | Record-only merge `1b4b0d8c18`; the DD watchdog tweak and SSmobs idle benchmark tweaks are dropped. |
| `w6/design`, `w6/audit` | MERGE | Docs: `doc/medical_frameworks.md` (as-built, marked against OM), `doc/medical_audit_findings.md`. |
| `rewrite/mobsrc` | MERGE | Mob-state clobber fixes; CANPUSH suppression and alpha sources are contributions (EFFECT_UNPUSHABLE, EFFECT_ALPHA_MULT). |
| `rewrite/c10` (+ `rewrite/c6`) | MERGE | Latency policy, pins, storability sandbox; the collapse sweep runs on PERIODIC_SLOW. Its weakref blocker was removed at the i7 merge: this tree has no `/datum/weakref`, so the gap it closed does not exist. |
| `rewrite/benchstore` | MERGE | Shared bench store, COUNT/TIMING metrics, `bench-baseline`, dd-slot lanes. Its SSmachines `processing_work_items()` override was removed at the i7 merge (no `processing_machines` list). |
| `rewrite/p5` | MERGE | Borg player abilities as interaction abilities, on OM relation accessors. |
| `rewrite/grants` | SUPERSEDED | Ability grants moved onto `om_grant()` (`43477cf717`); the branch's generic grant store duplicates the OM contribution store. |
| `rewrite/lintfix` | PARTIAL | The `check_grep.sh` PCRE2 fix; its adapter/allowlist halves were obsolete. |
| `rewrite/i7` | MERGE | Compact `INTERACT_*` interaction specs; devices, assembly and structures converted (`c42dba9963`). The same merge fixed three compile breaks carried in by earlier merges (weakref blocker, `processing_work_items`, vtec `remove_verb`). |
| `rewrite/c11` | MERGE | Spatial API (`turf_contents_of_type`, `locate_on`, `area_contents_of_type`), the raw contents/locate ratchet (`spatial_lint.py`, now in `check_ratchets.sh`), and slots for disposals, vehicle cages and transit pods, declared as `/datum/om/relation/slot` (`2fb390976d`). |
| `rewrite/s4` (+ `rewrite/s4base`) | SUPERSEDED | Moved SSobj/SSprocessing users onto REACT_*; this tree already retired START_PROCESSING onto OM periodics and `om_after`, and migration_plan.md deletes the reactor. Its alloy-transfer fix targets a cooling rate model that no longer exists. |
| `rewrite/fix5` | SUPERSEDED | Both fixes already here: food replicator guards a zero rating; `rust_set_turf_device()` unregisters a non-turf arena handle. |
| `rewrite/life-bench-base`, `rewrite/life-bench-master` | DROP | Old-side baselines of master's SSmobs Life for `life_on_om_benchmark.md`; merging them would bring SSmobs Life back. Kept as benchmark references. |
| `codex/main-tree-wip` (431 files) | PARTIAL | A parallel object model (`code/datums/object_model`: archetypes, behaviours, `om_claim`, `EnsureAfter`/`ObserveSet`, generated stats and UI schemas), a parallel Life scheduler (scheduled_life, wake events, biology catch-up), body/afflictions on that model, SSreactor scheduling priorities and matching Rust/binding changes: dropped. Ported (`02e4cbe025`): wires as an owned child through `/atom/declared_owned_vars()` (20 hand-written `qdel(wires)` blocks gone), `declared_owned_vars()` overrides that dropped `..()`, per-type `state_nondeterministic_list_vars()`, the preferences cache fix, SSvg bounds check, typed hotspot neighbours, casino `usr` shadowing, and `tools/dm-health` with its module READMEs and the type annotations its tests read. Record-only merge `75157da925`. |
| origin-only branches (`LINDA-rewrite`, `claude/atmos-perf-gc-review-*`, `combat-*`, `integration-wip`, `nanomaps_generation`, `retarget/combat-overhaul`, `tgui-migration`, `rewrite/c1 c3 c4 c7 d3 d4 d5 h1 i2 i3 i4 i6 l2 l3 m1a m3 m4 m5 matter-static memlists memlists2 p3 p4 r6 r7 s1 s2 s3`, `wave1/l1`, `local/master-check`, `localmaster`, `origin-local/master`) | MERGE (already) | Every one is 0 commits ahead of this branch. `upstream/*` is the CHOMPStation upstream, not rewrite work. |
| `rewrite/api-cleanup`, `boot-perf`, `p2-destroy`, `p2-prompts`, `p2-qdel` | out of scope | Live Phase 1-2 tracks off `rewrite/om-integration`, being committed by other sessions today; they merge into om-integration themselves. |
| worktree `dq-w5-integrate`, `dq-w6-audit`, `dq-w6-design` | MERGE (already) | Clean; heads contained. |
| worktree `dq-w6-integrate` (5 uncommitted files) | PARTIAL | `is_dead()` for vital loss, `set_organ_tag()` for regrown organs, `die()` in the vital tests (`07be9d5d01`); its body-time and containment allowlist edits dropped (lint gone / regenerated). |
| worktree `CHOMPStation2-body-baseline` (149 dirty files) | SUPERSEDED | An earlier copy of the Codex main-tree work (131 files identical to the snapshot, 18 older versions); covered by the `codex/main-tree-wip` triage. |
| worktree `CHOMPStation2/.claude/worktrees/review-fixes` (110 dirty files, 2026-09-03) | PARTIAL | Ported onto the OM architecture (`1eafbecba3`): combat-AI idle behaviours, contract/budget/alloy/preference exploits, expedition evacuation and generated-station robustness, machine wake-after-power, melee swing through `attack()`, forcewall double `on_hit`, tgui persistence. Dropped: SSmachines hibernation tables, APC reactive power, door timed processing, synchronous generation spins, the work-temperature metallurgy model, counteroffers, `verdigris/atmos`, CLAUDE.md edits. |
| worktree `C:/Users/bmene/.codex/worktrees/dmb-format` | ACTIVE, not merged | Untracked `tools/dmb` (DMB/RSC reader-writer, OpenDream opcode matrix) was being edited minutes before this pass; it is independent tooling for its own session to commit. |
| `%TEMP%/dq-bench-baseline-*` | gone | No such directories exist any more. |

## 2. Follow-ups this pass leaves open

- **w5 hibernation rules still polling.** Organs, blood, addictions, phobias, NPC, NIF, weight, changeling, shock, medical, heartbeat, thermoregulation, radiation and mutations need producers on their stage's `wake_on` channels before they can `idle()`.
- **Grants.** Languages, factor grants and the mind-transfer hook still use their pre-OM paths.
- **Verdigris provenance** (from the Codex snapshot: `tools/build/lib/verdigris_provenance.ts`, `verdigris/verdigris/build.rs`). It stops a stale or mismatched DLL from being reused, but it makes `DQ_PREBUILT_VERDIGRIS=1` refuse a DLL copied without its sidecar, so porting it needs every worktree's copy step updated at the same time.
- **dm-health baseline.** `tools/dm-health/baseline.json` was taken on Codex's tree. The first CI run of `dm-health ci-suite` will report differences; regenerate with `--write-baseline`. Its Rust tests pass (201).
- **Lint gaps found while rebasing ratchets.** `lifecycle_counts_lint.py` strips comments before looking for `// LIFECYCLE:`, so no Destroy can be justified that way. The ceilings raised in this pass are listed in commits `cdaac8cabf` and `1eafbecba3`: 9 admin VV prompts, the expedition objective's undeclared `tracked` list, and qdel counts in cryo, species, shapeshift, the balance harness and the defenders.
- **Dead generated-station procs** (`fill_exterior`, `carve_departments`, `carve_corridors`, `enclose_corridors`, `is_interface_door_candidate`, `place_interface_door_run`) have no callers.

## 3. Proposed deletions (not done; the user decides)

Unlink directory junctions before `git worktree remove`, or the removal also
deletes the main tree's `node_modules`.

- **Local and remote branches fully contained here:** `w5/integrate`, `w6/integrate`, `w6/audit`, `w6/design`, `rewrite/i7`, `rewrite/c10`, `rewrite/c6`, `rewrite/c11`, `rewrite/benchstore`, `rewrite/mobsrc`, `rewrite/grants`, `rewrite/p5`, `rewrite/lintfix`, `rewrite/fix5`, `rewrite/s4`, `rewrite/s4base`, `rewrite/ledger-joint`, `codex/main-tree-wip` (and `origin/rewrite/s4`, `origin/codex/main-tree-wip`), plus every 0-ahead origin-only branch in the table above. Safe once `rewrite/reconcile` is merged into `rewrite/om-integration`.
- **`rewrite/life-bench-base`, `rewrite/life-bench-master`:** tag them first (for example `bench/life-old-base`, `bench/life-old-master`), since `life_on_om_benchmark.md` cites their commits; then delete the branches.
- **Worktrees:** `E:/projects/dq-w5-integrate`, `dq-w6-audit`, `dq-w6-design` (clean); `dq-w6-integrate` (its 5 dirty files are ported, so they can be discarded); `CHOMPStation2-body-baseline` (dirty files are an older copy of the Codex snapshot, so they can be discarded); `CHOMPStation2/.claude/worktrees/review-fixes` (ported, so it can be discarded). **Keep** `C:/Users/bmene/.codex/worktrees/dmb-format` (active).
- **Main tree `E:/projects/CHOMPStation2` uncommitted changes:** see §4.

## 4. The main tree's uncommitted changes

`E:/projects/CHOMPStation2` sits on `master` (`d58f79336c`) with 372 changed
paths. Compared file by file with `codex/main-tree-wip` (pushed to origin):

- 278 of the 281 modified tracked files are byte-identical to the snapshot
  (line endings aside). The other 3 were a path-quoting artefact of the
  comparison and are identical too.
- 2 tracked files are newer than the snapshot: `code/__defines/verdigris/_bindings.dm`
  and `verdigris/domains/gas/src/lib.rs`, each with 4 extra `dm-health:`
  return-type comments. `_bindings.dm` is generated, and this tree's
  generator does not emit those tags, so they are not ported.
- All 150 untracked files are in the snapshot; 148 are identical. The other
  two, `tools/dm-health/src/symbols.rs` and `typing.rs` (edited 02:41, after the
  00:37 snapshot), are newer; those versions are what is committed here
  (dm-health tests: 201 pass).

**Verdict: the main tree's uncommitted changes can be discarded.** Everything
in them is either ported here, preserved on `codex/main-tree-wip`, or
deliberately dropped. Nothing has been written there since 02:41, but check
that no Codex session is still using the main tree before discarding.
