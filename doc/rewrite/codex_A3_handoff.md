# A3 objects init audit

Worktree E:/projects/dq-wt/codex-A3, branch codex/A3, base 274d176a88.
Before: init_lines368, world_reads9. Analyzer confirmed204 init_lines and1 world_reads;172 rows removed. Global init baseline4115→3943;decl47→44 (three init_visuals removed).
47 production files, six real-constructor tests in code/modules/unit_tests/dq_a3_initialization_tests.dm (root adds manifest); selectors dq_a3_initialization/* plus dq_look_pin and existing focused structure/effect coverage.

Converted coherent completed-init jobs to native setup: weather footprint/telegraph collection, anomaly countdown startup, renderer animations/filters, tile refresh, event sounds/announcements, countdown child attachment, particle renderer realization/owner linking, coordinate landmark registration, target/lock discovery, loose-content collection, canvas grid, and constructor-independent presentation/rotation work. Protected TRACKED/ownership/reference declarations and setter-call text remain unchanged. Existing destruction/lifetime hooks untouched. Existing inactive root /obj and /obj/item initialization order retained. No new base vars, ALLOW annotations or shadow state.

Cross-task overlaps: landmark JoinLate registry_join branch is unchanged for root D5; only named coordinate recording and five special spawn-coordinate directories moved. D3 overlap: lattice icon_state becomes latticeblank, pod state becomes nt_pod; additionally lattice's unconditional smoothlattice.dmi runtime icon becomes the type default. This intentionally updates editor/type defaults while preserving ordinary initialized runtime. Exact 3-decisecond looping animation intervals use 0.3 SECONDS.

## Complete remaining file inventory and reasons

Numbers below are source identity estimates, not analyzer results.

- anomalies/_anomalies7: area placement and discard guard, plus core frequency/code/type configuration. Core settings belong to its existing declared child and native child rolls would touch A2/protected setter/declaration sites; no side-effectful generator. Countdown/lifetime setup moved.
- anomalies_hallucination2: decoy creation uses one chance per adjacent turf and creates independent peers (not owned children). spawns_many requires an owns_many output and would change lifetime policy; preserve correlated construction/filters until a peer-placement declaration exists.
- dark_growth2: check_glow is derived in init, after rolls; multi-overlay chance/color selection also serves runtime crossings. A preinit roll would read the wrong gate; no shadow image/roll state introduced.
- Cleanable/fuel17: constructor spill context, required admin/game logging, pre-parent merging into another holder and conditional Spread; ordering depends on which instance is initializing. No pure keeps_if logger contract or early merge form.
- Cleanable/humans14: blood's mapload-specific drying, forensic merging, delete_me/unfinished-peer arbitration. Moving just one phase changes constructor ordering and timer parity. Drip registration moved.
- Cleanable/misc25: dirt's mapload RNG, turf mutations, simultaneous unfinished-peer coalescing and discard; old blood colour writes use a protected setter and its runtime RNG helper. No generation/duplicate raw state introduced.
- decals/cleanable2: pre-parent persistence registration uses mapload, absent in post-init setup; retain exact registration order.
- landmarks4: only JoinLate switch/registry/simulated branch left for root D5. Named coordinate registrations are setup.
- landmarks_poi1: INITIALIZE_IMMEDIATE queue entry precedes parent init; preserve immediate resolver ordering.
- map_effects/beam_point3: pre-parent beam creation and mapped initial delay, consumed by parent interval initialization. No equivalent earlier declared peer creation.
- map_effects/portal1: find_lines binds mapped peer relations before parent; preserve reciprocal registration order.
- effects/misc1: lightning fade explicitly begins before parent lifetime init; no pre-parent presentation setup contract.
- particle_holder3: null-location stack_trace/QDEL guard remains. Valid holder installation is setup; no logger removed or side effects placed in a pure predicate.
- temporary_visuals/miscellaneous13: decoy copies keep=FALSE constructor parameters (dropped before setup); circle-wave animation is deliberately before parent random-facing/init. Fading-decoy animation moved.
- items.dm8: /obj/item base interning, action registration and combat-derived embed chance are consumed by child Initialize. Preserve base-type order and reserved base state.
- mail1: junk_mail creates random paired package/name/content state using an existing ownership field. Proper native starting contents need that protected declaration and a correlated naming/content protocol; no rename-only conversion.
- micro_structures1: /obj_instance_setup base initialization is shared with table_initialize fast path; retain parent/fast-path parity. Micro-tunnel offset placement moved.
- mob_spawner1, trash_pile1: randomized initial cooldown distinct from future spawn_delay. Current rolls can only write a holder var, while cooldown is sparse timed state; adding a persistent roll-delay shadow would change state contract.
- catwalk9: delete_me and unfinished-peer arbitration plus neighboring connection work; pure keeps_if cannot preserve those effects/order.
- cliff3: danger registration must precede mapload-specific turf-edge refresh; preserve map/live refresh parity without saving a duplicate mapload flag.
- secure_closets6: constructor owner view and current-body portrait, not a constant; owner/keep context remains per-instance.
- statue23: actual living constructor subject is keep=FALSE; petrification/unbuckling/stasis setup must run while it is available. No dropped-param work moved to setup; D4 source left untouched.
- droppod3: transient cargo constructor input and podfall start; keep in constructor rather than add stored references.
- fence2: mapped cut/door status established before parent initialization; preserve parent consumers.
- grille2: randomized starting integrity after parent resets integrity, then broken-state transition. Preinit rolls would be overwritten by parent; do not add a shadow integrity variable.
- lattice14 (including last world_reads1): terrain/duplicate guards and mapload-vs-runtime smoothing. Mapped instances draw immediately without thousands of queued neighbor timers; setup lacks mapload context, so keep exact timing. Two constants moved to defaults.
- mirror3: transient building argument makes an empty frame; preserve constructor state.
- beam_prism2: mapped bearing animation/state; constructor-only instance bearing left. Preset controller linking moved.
- props/machines12: NTpod's visual mask/layers must exist before mapload gathering immediately invokes abduction/change_state; setup would be too late without retaining a duplicate mapload flag. Constant state moved; no mask ownership/declaration edits.
- railing2: per-instance constructor constructed/anchored state remains; rotation registration moved.
- reflectors1: cold canister gas temperature follows parent gas creation (A4 deliberately retained that initialization ordering). Reflector presentation moved, cold child remains.
- salvageable: its independent table factory is now a setup job, preserving the unowned peer policy; see the 2026-10-15 follow-up.
- watercloset3: biowaste crusher link precedes parent creating/using its owned muffinmonster; follow-up creature configuration preserves that constructor sequence. Toilet plumbing moved.
- windoor_assembly7: constructed/start_dir binding remains while subsequent controls/tile refresh are setup.
- window5: mapped/constructor anchoring, state and initial direction remain. Later controls/tile publication moved.

No builds, tests, generators, analyzer jobs, baseline edits, commits, merge or push performed by this agent. git diff --check, new-block cross-tree uniqueness and new-proc duplicate audits are clean. Root owns one serialized validation batch and final handoff.

## Exact retained site identities

[Committed residual inventory](codex_A3_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.


## Residual follow-up, 2026-10-15

The personal salvage terminal now declares its existing reinforced-table factory through setup(PROC_REF(prepare_terminal_table)). Its complete post-parent body is unchanged, there are no descendant Initialize consumers, and the job reads only the durable location. No ownership or reference declaration is required or changed: the supporting table remains an independent peer and survives deleting the terminal. The previous report unnecessarily limited the replacement to spawns_many().

New focused selector /datum/unit_test/dq_a3_initialization/salvage_table checks actual constructor output, exactly one newly created table, its location and independent lifetime. No generation/analyzer/build/test was run; shrink-only baseline update and the lane-ready proof are pending.
