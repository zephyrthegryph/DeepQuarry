# Evaluation: tracking, reads, Life/draw wakes, refs, init, process (2026-10-12)

Read-only; nothing built or run. Evidence is file:line or a count from grep/git. Items marked (unverified) were inferred, not traced to code.

## 1. Generated reads

- Generator: tools/analyze/src/gens/reads.rs (476 lines) over the read walker tools/analyze/src/sem/reads.rs (1425 lines). Output reads.dm holds three global lists: interned names, roots, and a table keyed "<type>::<proc>" (gens/reads.rs:1-16). Keys are interned integers, so runtime has no vars[] or text lookups.
- Dependency classification (sem/reads.rs:403-415). A var is Reactive if tracked, a relation, a stat or a derived value. It is Constant if never written anywhere or `const`. Otherwise it is Unknown, and Unknown becomes an untracked read. Weakness: "never written" is judged by var name across the whole tree (`written.is_written(var)`, line 411), so a name shared with an unrelated written var makes a constant look Unknown. That errs toward false positives, which is the safe direction.
- Documented non-subscriptions (sem/reads.rs:15): `A.args`, `world.time` and GLOB reads never subscribe. GLOB reads are only flagged if unannotated (`unannotated_global`, gens/deps.rs:28). An annotated global (`// ALLOW(reads)`) is trusted by hand.
- OPAQUE directories (gens/reads.rs:30) are not walked: code/datums/sys, om, capabilities, reactions, ownership, code/engine, and Verdigris bindings. Anything routed through them yields `?opaque:` and is re-asked on demand, not subscribed. Stale risk: a condition that reads a Rust-owned value (SMES charge) is polled or re-asked, never pushed.
- List contents: `TRACKED` setters compare with `==` (code/__defines/capabilities.dm:40-42). A list var assigned the same list ref reports unchanged. In-place mutation (LAZYADD, `+=`, `-=`) bypasses the setter. tracked.rs counts only `V = x`, compound ops and `V++/--` (tracked.rs:8-14). I found no rule for list mutators on a tracked list var. The walker does handle list relations as `name[]` hops (sem/reads.rs:92, 303), so relation lists are covered and plain tracked lists are not (unverified for specific vars).
- Cross-object reads: only relation hops are followed. Hops through non-relation vars are `hop_not_relation` errors (gens/deps.rs:28). `every(when=)` gates with a relation hop use a dedicated hop watch (engine/actions/every.dm:372-377). This is solid for relations and absent for turf neighbours and area state (see KD90 in framework_gaps.md:284, which says `look.neighbours()` does not cover a turf's own vars).
- Baseline tools/ci/untracked_inputs_baseline.txt: 2281 lines, 2279 sites. 1859 are `draw_untracked` and 420 are `stat_input_untracked`. Top files by site count:
  - human/update_icons.dm: 318
  - floor_icon.dm: 231
  - simple_mob/appearance.dm: 135
  - clothing.dm: 83
  - mob.dm: 51
  - access.dm: 44
  - bed.dm: 41
  - forensics_crime.dm: 40
  The mass is in draws of mobs, turfs and clothing. These are the highest-churn visuals and the likeliest places for stale appearance.
- Performance: nothing was measured (no benchmarks by policy). The design cost is one typed accessor call per read plus a per-handler rank order. The generated tables are built through GLOBAL_LIST_INIT with builder procs of at most 300 rows (gens/deps.rs:248). At this scale that is boot-time list construction. Runtime cost is unknown.
- Lint header drift: tracked.rs:1-4 still documents `TRACKED(T, var, channel)`, but master's macro is two-argument (capabilities.dm:42). `TRACKED_BRIDGED` (line 54) remains as the channel bridge.

## 2. Change tracking end to end

- Setter: `TRACKED(T,V)` defines `set_V` with `TRACKED_UNCHANGED`, which is `(OLD==NEW) && (isnull(OLD)==isnull(NEW))` (capabilities.dm:40). That fixes the null-vs-0 problem for the generated setter. Hand-written `SETTER` bodies and `TRACKED_SCHEMA` (engine/declare.dm:72) have their own compare (schema path calls the same macro). Hand-written setters are the only remaining null/0 risk (unverified per setter).
- Publish path: `tracked_changed` calls `state_changed(E, 0, var_name)` (engine/change/state.dm:90-92). The bridge `tracked_bridged_changed` still maps vars to CHANGE_* channels via `fields_of` (state.dm:97-99).
- Legacy residue: 415 `CHANGE_*` token occurrences in 116 files, and 1222 lines matching `changed(`/`CHANGE_` in code/. These are removed only with the OM "S4" step.
- Size: 1286 `TRACKED(` declaration lines. I found no duplicate declaration lines by exact text, but my check was lexical only (it could not see two declarations of the same var on different types).
- Life steps: air watch (code/modules/mob/living/life/air_watch.dm) arms one Rust band watch per mob on the gas mixture of the turf it stands on, with levels from species limits. Rust reports only a crossing, and `air_changed_here()` publishes MOB_KEY_AIR. The watch is re-armed by the Life steps themselves when they run, "after every move: MOB_KEY_LOC" (air_watch.dm:9, life_steps.dm:13). Each step lists `woken_by` (life_steps.dm:14-41).
- Missed-wake risk (matches the reported gap). The watch is bound to the mixture's arena id (air_watch.dm:60-66). The re-arm key is `id|levels_key` and skips if unchanged. When a door or firelock opens, the mob's turf can merge or change mixture without the mob moving. Whether the id changes depends on LINDA/Rust internals. If it does not change, nothing re-arms. If the mob is asleep, nothing runs. The door case is not covered by any test I found (grep for neighbour or re-arm in the breath-hazard and gap tests returned nothing relevant). Verdict: plausible gap, not proven from code alone.
- Resting and embedded wakes: no test found by name (unverified).
- Polling remainders: `LIFE_WOKEN_BY_POLL` exists as an explicit escape (life_steps.dm:35: gravity changes under a standing player publish nothing, so the step polls). The `every()` gate with a proc but no tracked reads polls (`every_with_a_proc_gate_polls`). An `every()` with `when =` parks in `every_parked` (every.dm:142, 218) and wakes on the tracked reads of the gate. Gates that throw keep polling (framework_gaps.md:313).
- `every_parked` is stored as a list of indexes on the per-holder state. Wake does `S.every_parked -= index` and nulls the list when empty (every.dm:233-254). That is correct, but the wake runs on every publish of any read the gate has.
- Draw triggering: draws subscribe to the holder vars they read (`generated_draw_reads`, gens/deps.rs:12). Turf draws read neighbour turf vars the engine cannot hear (framework_gaps.md:284). That row is marked DONE, but 231 `draw_untracked` sites remain in floor_icon.dm. So adjacency masks are still partly manual (`appearance_notify_neighbours`).
- Redraw storms and double redraw: no coalescing evidence was checked beyond the existence of engine/actions/coalesce.dm and change/batch.dm (unverified for draws). Ordering between derived values uses rank (gens/reads.rs doc). Cycles are not documented in what I read.

## 3. References

- doc/rewrite/state.md:87-90 claims registry IDs are typed and weak, and cite 428 hard deletes at about 140 ms each in a profiled round. That is the baseline motivation.
- Ownership lint (tools/analyze/src/lints/ownership.rs, 735 lines) covers accessor use: `raw_write`, `contradiction`, `kinds`, `matrix`, `handle`. It checks that entity vars are written through ownership accessors. It does not check "does this var that holds a datum have a destroy-time clear". I found no ref-storage lint in lints/mod.rs (grep for ref_storage, stored_ref, weakref: no hits). Gap: nothing stops a raw `var/obj/x` from holding a strong ref.
- Cleanup on qdel: relations are cleared by the ownership core (not read in detail). `own_clear(B, nameof(B.air_watch), OWN_DELETE)` in air_watch.dm:66 is the pattern.
- Hard-delete sources: no current census read. state.md only gives the old figure.

## 4. Initialize migration

- `Initialize(` appears on 768 definition lines (code and maps) and 1197 lines overall including `..()` calls.
- `ALLOW(init/...)`: 214 total. INSTANCE_STATE 205, FRAMEWORK 9, CTOR_ARGS 0. So 96 percent of kept overrides are the catch-all category, which makes the category near meaningless as a triage signal.
- `LateInitialize` or `INITIALIZE_HINT_LATELOAD`: 3 remaining lines. `after_init(`: 584 uses.
- tools/ci/init_baseline.txt: 4353 lines (4247 `init_lines`, 104 `world_reads`).
- The jump from about 1266 to 4353 is a format change, not growth. Commit 99081ec0e2 changed the ratchet to count each imperative line inside an Initialize override (`init_lines`) instead of one row per override, "baseline seeded at the switch". Counts then fell by 8 to 10 pass days: 7674 (10-10) down to 6050, then 4353 after "Shrink baselines after merging master". So real work is shrinking it, but the baseline oscillates 6050 to 4353 each time a branch merges master without shrinking (see section 5).

## 5. Process friction (last 5 days)

- 1373 commits in 5 days; 375 start with "Merge". Roughly 27 percent of history is merges.
- `code/modules/unit_tests/snapshots/look_keys.txt` is 21044 lines, touched by 145 commits in 5 days. Many subjects are literally "Regenerate look_keys.txt for the merged tree" (at least 25 visible in a filtered log). Every merge conflicts or invalidates this generated snapshot. Also "Lower the base_vars baseline; look keys" appears repeatedly.
- Baseline churn: init_baseline touched by 12 plus commits in a day, flipping 6050 and 4353. Commit subjects "Shrink baselines after merging master" and "Lower the init baseline after the merge" repeat. Baselines are committed and shrink-only, so any parallel branch conflicts.
- Repair commits: "Repair acceptance ...", "Resolve the conflict markers left by the merge", "Fix the bv-traits merge ... base_vars and init baselines", and a "push stamp: a trial-merge conflict only in regenerated files is no conflict" workaround. A conflict marker did land in a commit.
- known_failures.txt is small: 2 entries, both dq_hc_computers (operating_toggles and operating_thresholds), failing on master for "a life sequence step outruns its state table (seq_snapshot_note list index out of bounds)". That is a real Life bug in an area this evaluation covers. The file was touched by 13 commits in 5 days, so it churns even though it is small.
- Tests never run: by policy workers skip full suites, and only focused tests run (memory notes). Gaps such as door-open and resting wakes rely on someone writing a focused test.

## Top 10 findings by severity

1. Life air-watch re-arm gap: the watch is re-armed only when the steps run (air_watch.dm:9, 60). A door opening beside a sleeping mob may change its air without a re-arm. No test covers it.
2. Tracked lists mutated in place (LAZYADD, `+=`) bypass setters and no lint catches them (tracked.rs counts assignment and compound ops on the var only).
3. 1859 `draw_untracked` sites remain (318 in human/update_icons.dm, 231 in floor_icon.dm). Cached appearances can go stale. KD90 is marked DONE while the baseline is still huge.
4. Turf/neighbour/area reads are not heard by the read engine (framework_gaps.md:284). Adjacency masks depend on manual notification.
5. No ref-storage lint exists. Hard deletes are only measured by a historic figure (428 per round, state.md:90).
6. Real bug already on master: known_failures lists a Life sequence step outrunning its state table (list index out of bounds) in dq_hc_computers.
7. look_keys.txt (21044 lines, 145 touches in 5 days) is a committed generated file that is conflict-bait on every merge. This is the single largest source of process friction.
8. Baseline files committed and churned on each merge: init_baseline moved 6050 to 4353 repeatedly. The 1266 to 4353 growth was a counting-rule change (99081ec0e2), but the merge-and-shrink churn is real.
9. ALLOW(init/) categories are 205 of 214 INSTANCE_STATE; the category carries no information. 768 Initialize definitions remain.
10. Legacy bridge still wide: 415 CHANGE_ tokens in 116 files, `TRACKED_BRIDGED` still defined, and the tracked lint header documents the old three-argument form. Hand-written setters can still reintroduce the null-vs-0 bug (the generated macro is correct).
