# Medical / body audit findings tracker

Covers `code/modules/body`, `medical`, `organs`, `surgery`, `reagents`, mob life, human
life/death/species, silicon/robot, brain/MMI, protean, resleeving and vore's body
interactions. Part 1 tracks the four earlier bug audits (re-verified against branch
`w6/audit`, from master `59ca56beef`). Part 2 is a new audit for duplication,
scattered checks, coupling and bad functions.

## Re-triage 2026-09-27 (MED-1)

Every row re-checked against `rewrite/reconcile` (newest medical code, Life on OM pipelines);
the **Status 2026-09-27** column holds the result. 147 rows:

| Status | Rows |
|---|---|
| FIXED before this pass (w6/critical, reconcile) | 23: A1-A4, A6, A8, A9, A20, A25, B4, B11, C3, C19, D1, D3, D5, D6, P2-D1, P2-D2, P2-D4, P2-D12, P2-S8, P2-K7 |
| FIXED (MED-2), on `rewrite/b-medical` with regression tests | 8: C1, P2-F8, A10, A7, D13, D14, D15b, D16 |
| INVALID (the life scheduler they describe was replaced by OM pipelines) | 3: A11 (persistent frames), A17 (`LIFE_HALT` gone), A18 (`no_sleep` gone) |
| FIXED (MED-3), on `rewrite/e-medical` with regression tests | 40: B3, B5, B7, B8, B9, B10, B12, B16, B17, B18, B19, B20, B21, B22, B23, C2, C4, D2, C5, C6, C7, C8, C9, C14, C15, C17, C21, C22, C23, D7, D8, D9, D11, D18b, D21, D22, A5, A22, P2-F7, P2-F9 |
| STILL OPEN | 73 |

P0 list status: all five items are closed. P2-D4 and A8 were already fixed by the sealed
`death()` pipeline (guard first, `on_revived` restores simple mobs); a regression test for the
double call was added anyway. A25 is fixed but an empty view may still tick (see A19).
P2-F12 is half fixed (`is_lethal()` exists; `isSynthetic()` still reads robolimbs).
C11/C13 changed shape: `invalidate()` now raises `om_changed` on every call.

## MED-3 / MED-5 / MED-6 (2026-09-27, `rewrite/e-medical`)

- **MED-3:** every P1 row listed above is FIXED (MED-3) with a regression test in
  `code/modules/unit_tests/dq_medical_p1_tests.dm` (written, not yet run). Notes on choices:
  B12's cold branch keeps the warm branch's magnitude (scaling both by `removed` is B15/NEW:HEAT);
  B22 keeps the suit's "injection port" delay (can_inject() is called with ignore_thickness);
  C6 makes dispatcher-owned afflictions (`metric_owned`) presentation-only for treatment;
  C9 adds `systemic_singleton` (respiratory arrest, arrhythmia); D9 keeps a trend baseline per
  device, moved by explicit scans (printout, analyzer use) only; D21 adds
  `set_species(keep_organs = TRUE)` for the nymph.
- **MED-5 (partial):** factor-only modifiers are `/datum/body_effect` flyweights applied as OM
  contributions (`EFFECT_BODY_EFFECTS`) that expire on the body clock, so stasis pauses them
  (`code/modules/body/body_effects.dm`). 63 types converted; the poisoned DoT modifier family is
  the `lingering_poison` affliction. `add_modifier()`/`has_`/`remove_` forward body-effect paths.
  Ratchet: `tools/ci/check_grep.sh` caps `/datum/modifier` types at 165.
- **MED-6:** the w5 life stages listed under "w5 hibernation rules still polling" in
  `doc/rewrite/reconciliation.md` have idle rules and rewake backstops.

## Destinations

| Tag | Meaning |
|---|---|
| CRIT | Already being patched on `w6/critical`. |
| CLOCK | Holder-provided clocks: body clock, stasis, on-read organ decay, timers/scheduler, no `process()`/`addtimer`. |
| OWN | Ownership completed: organs, limbs, implants and embedded objects on the ledger hierarchy; ordered destruction; one `return_from_death()`; lifecycle test harness. |
| NULL | Nullspace elimination. |
| EXPO | Exposure/pharmacology model: routes and compartments, one `effective_dose` with allergy/species/biology gates, effects as data, gases and radiation unified. |
| W6 | Grants/capabilities, traits and genes, breath profiles, species facts, vision, hunger/movement unification, `isSynthetic` removal, god-proc splits in human life/radiation. |
| C8B | Mech body host and machine occupant behaviour. |
| FIX | Standalone bug no framework removes. The row says what to do. |
| NEW:x | A proposed framework or predicate not in the list above (see Summary). |

A framework is only assigned when its design makes the bug impossible. If the bug could
survive the framework (a wrong constant, a missing check, a wrong branch), it is FIX.

Severity: **critical** (exploit, soft-lock, lost player, runaway state), **serious**
(wrong gameplay result), **debt** (architecture, no direct wrong result today), **perf**.

---

# Part 1: earlier audit findings (re-verified)

Every finding was re-checked against current code. None were stale or wrong, so none
are INVALID. Line numbers have drifted by a few lines in `medicine.dm`
(Hannoa is now 1642-1680). D2 duplicates C4. A8's double-death has a deeper root
cause, recorded as P2-D4.

## A. Mob life, species, robots

| ID | Area | File:line | Problem | Sev | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|---|
| A1 | robot HUD | `silicon/robot/life.dm:233-244` | Adds a new traitor `image()` to `client.images` every HUD tick and never removes them. Also calls `disconnect_from_ai()` and writes `special_role` every tick. | critical | CRIT | FIXED |
| A2 | protean | `body/plans/nanoform.dm:251-253`, `protean_rig.dm:363-370` | Only the rig's screwdriver can `open_panel()`. With no rig (deleted, or `enter_rig()` failed) dormancy is a permanent soft-lock. | critical | CRIT | FIXED |
| A3 | protean | `nanoform.dm:217-221` → `protean_form.dm:62-68` | `enter_rig()` drops the rig at `get_turf(H)`, so a dormant protean escapes bellies, closets and mechs. | critical | CRIT | FIXED |
| A4 | species | `human.dm:1262-1321`, `species.dm:799-802` | `set_species()` never removes the old species' components (forms, xenochimera, shadekin, radiation). | critical | CRIT | FIXED |
| A5 | robot | `robot_parts.dm:193`, `robot.dm:225-232, 403-416` | Suit-built borgs get a default cell from `setup_cell()` (the third `new` arg is ignored). `set_cell(chest.cell)` unregisters the old cell but never ejects or deletes it, and `mount.install()` overwrites `wrapped` without `uninstall()`. The orphan cell stays in contents. | serious | FIX: in `set_cell`, `uninstall()` the mount and `qdel` the replaced cell; skip `setup_cell()` for suit-built borgs. | FIXED (MED-3) |
| A6 | brain/MMI | `brain/brain.dm:63-76`, `MMI.dm:174-176` | `refresh_host_status()` treats "no tissue" as alive, so deleting an MMI's brain revives a brain-dead view; `MMI.Destroy` then kills it again. | critical | CRIT | FIXED |
| A7 | brain | `brain/brain.dm:112-115` | `backup_ping` verb dereferences `mind.name` and `record` without null checks. | serious | FIX: `if(!mind) return`; treat `!record` as the no-backup branch. | FIXED (MED-2) |
| A8 | simple mob | `simple_mob/life.dm:318-336` | `death()` has no already-dead guard (double loot on a second call) and clears `density`/`ghostjoin`/eyes/ghost pods with nothing restoring them on revive. | serious | FIX: return early if already dead; add a simple_mob revive hook restoring density, ghostjoin, eyes and icon. (Root cause of the double call: P2-D4.) | FIXED |
| A9 | robot | `robot.dm:280-292` | Borg destroyed with a mind and no turf: the mind moves into an MMI still inside the deleting robot. | critical | CRIT | FIXED |
| A10 | identity | `datums/character_identity.dm:125`, `mind.dm:498-501` | `/datum/mind/var/identity = new` is never null, so `mind_initialize()` always binds a blank identity over the body's. The adopt-the-body's-identity branches are dead, and pre-login `genetic_modifiers`, notes and `time_of_death` are lost. | serious | FIX: default the mind's `identity` to null. | FIXED (MED-2) |
| A11 | life scheduler | `life/scheduler.dm:44` | `new /datum/life_context` every `Life()` of every mob. | perf | FIX: one reusable context, reset per cycle. | INVALID |
| A12 | life scheduler | `life/living_systems.dm:93-95` | Trait systems call `GetComponents()` (fresh list) per tick. The `forms` trait system has no `idle()`. | perf | FIX: `GetComponent` for unique types; add a `forms` idle rule. | STILL OPEN |
| A13 | human HUD | `human/life.dm:1715-1749` | Health doll rebuilds a `mutable_appearance`, per-limb images and a list every HUD tick. | perf | FIX: cache a key (limb bands, fire, trauma band) and rebuild on change. | STILL OPEN |
| A14 | human HUD | `human/life.dm:1614`, `1518`, `1688` | `get_species() in list(...)` allocates every tick; 11 global HUD objects are removed and re-added to `client.screen` every tick. | perf | FIX: change screen objects on state change only. (The species check itself is S5.) | STILL OPEN |
| A15 | robot HUD | `silicon/robot/life.dm:317-322` | `update_items()` rebuilds the screen list every tick. | perf | FIX: call it from equip, unequip and module change. | STILL OPEN |
| A16 | robot HUD | `silicon/robot/life.dm:248-249` | `T.return_air()` with no null check; a borg with a client in nullspace runtimes every tick. | serious | NULL | FIXED (MED-7): `T?.return_air()` in the robot HUD stage. |
| A17 | life scheduler | `ai/life.dm:23-24, 48-49`, `pai/life.dm:17, 31`, `alien/life.dm:7`, `scheduler.dm:82` | `LIFE_HALT` returns before the sleep step, so dead AIs and pAIs never hibernate. | perf | FIX: dead mobs block segments with a gate instead of halting, or let HALT sleep systems that did not run. | INVALID |
| A18 | life scheduler | `life/living_systems.dm:149-153` | `!loc` sets `ctx.no_sleep`, so every nullspace mob (body backups, stored shells) runs `Life()` forever. | perf | NULL | INVALID |
| A19 | brain | `brain/life.dm:33-46` | Brain views poll `refresh_host_status()` every tick and never sleep. Every MMI and posibrain ticks forever. | perf | FIX: drive status from tissue events (insertion/removal already call it) and add an idle rule `!emp_damage`. | STILL OPEN |
| A20 | revive | `organs/subtypes/machine.dm:89-92`, `brain.dm:71-76`, `living.dm:457-461` | Hand-rolled revive (`set_stat(CONSCIOUS)` + list swaps) with no timestamp reset or body check. | serious | OWN | FIXED |
| A21 | life composition | `physiology.dm:499-501`, `_life_system.dm:221`, `human.dm:1309` | Composition key is `"[type]|extras"` but `physiology/applies()` reads `body_type`, which `set_species` changes, and `recompose_life()` is not called. Latent while all human plans are humanoid. | debt | FIX: add `body_type` to the key and call `recompose_life()` after a plan swap. | STILL OPEN |
| A22 | robot vore | `robot_bellies.dm:1-19` | Multi-belly branch never resets `vore_light_states` (stale keys), and `sprite_datum` is not null-checked. | serious | FIX: reset `vore_light_states` first; return if `!sprite_datum`. | FIXED (MED-3) |
| A23 | human radiation | `human/life.dm:363-527` | 164-line radiation god proc with 7 `isSynthetic()` branches. | debt | W6 | STILL OPEN |
| A24 | human life | `human/life.dm:1312-1499`, `1509-1691` | `update_status` (187 lines) and HUD `tick` (182 lines) are god procs with no idle rule. | debt | W6 | STILL OPEN |
| A25 | MMI | `MMI.dm:209-219`, `mind_host.dm:87-91` | `release_mind()` leaves an empty view that ticks and blocks inserting a new brain. | serious | CRIT | FIXED |

## B. Reagents and medical items

| ID | Area | File:line | Problem | Sev | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|---|
| B1 | treatment | `body/body.dm:316-326` | `collect_reagent_volumes()` never reads `touching`, so topicals do nothing on skin. What reaches the blood heals but also does blood toxin. | serious | EXPO | STILL OPEN |
| B2 | treatment | `_reagents.dm:85-91, 179-181` vs `body.dm:292-308`, `factors.dm:295-303` | Tags and factors ignore the allergen, synthetic `affects_robots`, dead and species gates that `on_mob_life` applies. | serious | EXPO | STILL OPEN |
| B3 | blood | `organs/blood.dm:261-281` | `take_blood` into a container holding another donor's blood relabels the whole volume as the new donor. | serious | FIX: refuse to draw into a container with a different donor's blood, or keep a separate entry. | FIXED (MED-3) |
| B4 | sleeper | `Sleeper.dm:526-535` | `inject_chemical` never checks `chemical in available_chemicals`. | critical | CRIT | FIXED |
| B5 | claridyl | `medicine.dm:1564-1573` | `pick(...)` evaluates every side effect before picking one. | serious | FIX: `switch(rand(1,10))`. | FIXED (MED-3) |
| B6 | overdose | `_reagents.dm:214`, `toxins.dm:560` | `overdose_mod *= chemOD_mod` compounds on the reagent instance every tick. | serious | EXPO | STILL OPEN |
| B7 | Hannoa | `medicine.dm:1667-1680` | `<5` and `<20` branches nested under `<2` are unreachable; float `==`; no `treatment_tags`. | serious | FIX: flatten the chain; add `TREAT_TISSUE_REPAIR`/`TREAT_HEMOSTATIC` tags. | FIXED (MED-3) |
| B8 | Eden | `medicine.dm:1604` | `metabolism = 0`, so it never leaves the body. | serious | FIX: give it a real metabolism rate. | FIXED (MED-3) |
| B9 | trauma kit | `stacks/medical.dm:307-338` | `mend()` runs once per wound but only one charge is used. | serious | FIX: mend once after the loop; count a charge per wound. | FIXED (MED-3) |
| B10 | addiction | `carbon/addictions.dm:93-104` | SLOW check is a separate `if`, then SLOW reagents fall into the FAST `else`, addicting at the normal threshold. | serious | FIX: one `if / else if / else` chain. | FIXED (MED-3) |
| B11 | iron | `dispenser.dm:352`, `treatment.dm:94-95` | Iron only gives `TREAT_BLOOD_RESTORE` (shock severity), never `BF_BLOOD_REGEN`; copper has neither. | serious | FIX: add `factors = alist(BF_BLOOD_REGEN = ...)` gated by the species' blood reagent. | FIXED |
| B12 | drinks | `food_drinks.dm:1071-1072`, `dispenser.dm:180, 226` | Cold drinks: `bodytemperature - adj_temp*coef` with negative `adj_temp` adds heat, then `min(target, ...)` snaps to target. | serious | FIX: `max(target, T + adj_temp*coef*removed)`. (P2-S10 covers the raw write.) | FIXED (MED-3) |
| B13 | legacy heal | `medicine.dm:57-75, 746-803, 2138-2170`, `food_drinks.dm:1343-1351`, `dispenser.dm:26-33`, `other.dm:231-234` | Direct `heal_damage`/`remove_wound`/`mend_fracture` with no biology check (osteodaxon mends robotic bones). | serious | EXPO | STILL OPEN |
| B14 | radiation | `medicine.dm:1114-1115, 1135-1136, 2095-2096, 2114-2115` | Hyronalin/arithrazine/cleansers write `radiation`/`accumulated_rads` directly as well as carrying `TREAT_ANTIRADIATION`. | serious | EXPO | STILL OPEN |
| B15 | temperature | `medicine.dm:1369-1372`, `modifiers.dm:44`, `toxins.dm:447`, `food_drinks.dm:814-882, 1457-1467` | Direct `bodytemperature` writes not scaled by `removed`; leporazine double-dips with its tag. | serious | NEW:HEAT | STILL OPEN |
| B16 | Malish-Qualem | `medicine.dm:998-1026` | Toxin damage lacks `* removed`; `strength_mod` can be 0 (divide by zero). | serious | FIX: multiply by `removed`; guard zero. | FIXED (MED-3) |
| B17 | blood packs | `blood_pack.dm:39`, `blood.dm:383-385` | Pack data has no `"species"` key, so stock packs are compatible with every species. | serious | FIX: set `"species"` and `blood_colour` in the pack data. | FIXED (MED-3) |
| B18 | nutriment | `food_drinks.dm:52-55, 1075` | Injected nutriment feeds synthetics twice; `drink/affect_ingest` writes `nutrition` and treats the coefficient as a flag. | serious | FIX: drop the second add; use `adjust_nutrition(x * coeff)`. | FIXED (MED-3) |
| B19 | factors | `factors.dm:346-350`, `medicine.dm:235-236, 264-265, 1575` | A `species_factors` entry replaces the base table (prometheans on dexalin lose `BF_O2_CARRIAGE`); bloodburn inherits claridyl's factors. | serious | FIX: merge species tables over the base; clear `factors` on bloodburn. | FIXED (MED-3) |
| B20 | burn kit | `stacks/medical.dm:366-367` | The `affecting.open` check has no `return`. | serious | FIX: add `return ITEM_INTERACT_FAILURE`. | FIXED (MED-3) |
| B21 | Talum-quem | `drugs.dm:211-214` | Toxin damage only applies when `chem_strength_tox <= 0` (to toxin-immune species). | serious | FIX: apply always, scaled by `chem_strength_tox`. | FIXED (MED-3) |
| B22 | syringe | `syringes.dm:241-250, 325` | `can_inject` only runs for non-humans; the stab amount can be negative under 5u. | serious | FIX: call `can_inject` for every living target; clamp at 0. | FIXED (MED-3) |
| B23 | Lipostipo | `medicine.dm:1893-1896` | Copy of lipozilase: the weight-gain drug also drains nutrition; ±0.3 weight is not scaled by `removed`. | serious | FIX: make it add nutrition; scale by `removed`. | FIXED (MED-3) |
| B24 | perf | `body.dm:360`, `addictions.dm:63`, `medicine.dm:824/855/885/917, 960-966` | Per-tick list allocations in metabolism, addiction and the -daxon organ lists. | perf | FIX: static organ lists; reuse the volumes list. | STILL OPEN |
| B25 | withdrawal | `dispenser.dm:256, 265, 288` | Writes `M.pulse` (overwritten next tick); `to_chat(src, ...)` sends to the reagent datum. | serious | EXPO (the `to_chat(src)` line is a one-token FIX now) | STILL OPEN |

## C. Body core and afflictions

| ID | Area | File:line | Problem | Sev | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|---|
| C1 | synthetic | `conditions/synthetic.dm:49-57` | Thermal runaway is treated only by `TREAT_COOLANT`, which only a reagent gives, and silicons have no reagent holder. It climbs to 100 and keeps the borg unconscious until an admin rejuvenates it. | critical | FIX: add a tool tag (`TREAT_SYSTEM_RESTORE`) or cure it from `process_heat()` when `heat_debt` reaches 0. | FIXED (MED-2) |
| C2 | venoms | `toxicology.dm:22-25`, `creature_venoms.dm:22-23, 104-106` | `progression_rate = 0` poisons on simple bodies add load every tick forever. | serious | FIX: negative drift on the simple plan, or `TREAT_REGENERATION`. | FIXED (MED-3) |
| C3 | simple hypoxia | `body/plans/simple.dm:169-192` | Simple bodies' oxygen debt is never paid back. | serious | FIX: pay it down in the simple life tick when the air is suitable. | FIXED |
| C4 | needle | `instruments/resuscitation.dm:114` | `mend(TREAT_DECOMPRESSION, amount)` with no target heals subdural hematoma and compartment syndrome anywhere. | serious | FIX: pass `BP_TORSO`, or add `TREAT_PLEURAL_DECOMPRESSION`. | FIXED (MED-3) |
| C5 | bruising | `conditions/trauma.dm:10-16` | Deep bruising "heals on its own" but has `progression_rate = 1.0` and no regeneration. | serious | FIX: negative rate or add `TREAT_REGENERATION`. | FIXED (MED-3) |
| C6 | dispatcher | `organ_failures.dm:19, 47, 74, 98, 149`, `environmental.dm:21, 82, 159, 183`, `emergent.dm:116-117` | Treatment on organ/metric-owned afflictions is reset by the dispatcher next tick; cured ones churn. | serious | FIX: make them presentation-only (no `treated_by`) or have treatment act on the source. | FIXED (MED-3) |
| C7 | shock | `trauma.dm:90, 127-129` | Hypovolemic shock's declared `factors` are never read; `band_factors` is null until the first tick. | serious | FIX: fold `factors` into bands; set band 0 in `on_added()`. | FIXED (MED-3) |
| C8 | infection | `trauma.dm:440, 444` | Wound infection writes `severity` directly, bypassing `set_severity()` and its signal. | serious | FIX: use `adjust_severity()` inside `progress()`. | FIXED (MED-3) |
| C9 | dedupe | `vital_systems.dm:167-177`, `organ_failures.dm:169`, `analgesics.dm:29, 63`, `causes.dm:279` | Duplicates are only checked per location, so respiratory arrest can exist three times. | serious | FIX: canonical location (`systemic` flag or `pick_spawn_target`), or dedupe by type. | FIXED (MED-3) |
| C10 | biology | `body/plans/humanoid.dm:50, 290` | Systemic biology comes from `isSynthetic()`. | debt | W6 | STILL OPEN |
| C11 | perf | `body.dm:360`, `simple.dm:29` | `invalidate(BODY_DIRTY_TREATMENT)` every tick for every ticking body. | perf | CLOCK (regeneration read on-read from the body clock removes the per-tick invalidation) | FIXED (MED-7): regeneration is re-read into the snapshot at most once per CLOCK_BIO instant (`refresh_regeneration()`); the per-tick TREATMENT invalidation is gone from both plans. |
| C12 | perf | `body.dm:37`, `factors.dm:171` | Any reagent change re-runs `recompute_factors()` (full baseline copy). | perf | FIX: dirty factors only on a dose-band crossing or when a factor reagent appears or leaves. | STILL OPEN |
| C13 | perf | `body.dm:104`, `affliction.dm:178-182` | `invalidate()` calls `life_wake()` on every call. | perf | FIX: wake only when `dirty` gains bits. | STILL OPEN |
| C14 | stages | `causes.dm:180, 191, 202, 213` | Triggers declare `tier = "Severe"` for four afflictions with no `get_stages()`; stage stays null. | serious | FIX: add stage tables or drop the tier. | FIXED (MED-3) |
| C15 | dispatcher | `emergent.dm:303-306` | Sets `existing.active_symptoms = null` without resolving symptoms. | serious | FIX: add an affliction `clear_stage()` that resolves symptoms. | FIXED (MED-3) |
| C16 | fever | `infection.dm:52, 89`, `trauma.dm:433`, `synthetic.dm:46` | Four afflictions write `owner.bodytemperature` every tick; the coolant leak has no cap. | serious | NEW:HEAT | STILL OPEN |
| C17 | simple plan | `simple.dm:23-40`, `factors.dm:259` | Simple `life_tick` skips factor recompute; `COMSIG_LIVING_FACTORS_CHANGED` has no listeners. | serious | FIX: run the factor step on the simple plan; delete the signal. | FIXED (MED-3) |
| C18 | vitals | `vital_systems.dm:175-177, 255-260` | Respiratory arrest and pneumothorax rewrite `progression_rate` from `tick()` by polling. | debt | FIX: compute drift in `progress()` from events. | STILL OPEN |
| C19 | nerve | `conditions/limbs.dm:141-153` | Nerve damage rebuilds `symptom_pool` every tick. | perf | FIX: move to `configure(location)`. | FIXED |
| C20 | burn shock | `trauma.dm:372-377, 393-398` | Walks every limb twice per tick. | perf | FIX: cache total burn once per tick. | STILL OPEN |
| C21 | vitals | `vital_systems.dm:78-80, 159-161` | Airway/breathing factors re-dirty only per 10-point band; new `alist` each recompute. | serious | FIX: invalidate on every severity change for these types; reuse a scratch table. | FIXED (MED-3) |
| C22 | severity | `limbs.dm:97, 139, 196`, `trauma.dm:290` | `New()` hard-sets severity (concussion always 100). | serious | FIX: `initial_severity` applied in `on_added()`. | FIXED (MED-3) |
| C23 | attach | `body/parts/limb.dm:115-119` | `attach_part()` adds carried afflictions without `can_afflict()`. | serious | FIX: check on attach; convert or drop failures. | FIXED (MED-3) |
| C24 | teardown | `body.dm:83-85` | Body teardown runs `on_removed()` → invalidate/wake/signals on a deleting owner. | debt | OWN | FIXED (MED-7): a body whose owner is deleting only unlinks afflictions (`unlink_affliction()`): no on_removed, invalidate, wake or signal. |

## D. Organs, surgery, diagnosis

| ID | Area | File:line | Problem | Sev | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|---|
| D1 | cavity | `surgery/cavity.dm:25-44`, `surgery.dm:385-392` | Implant Object accepts almost any item, pre-empting syringes, needles and kits on an open chest. | critical | CRIT | FIXED |
| D2 | needle | `resuscitation.dm:114` | Same as C4 (untargeted decompression mend). | serious | FIX (dup of C4) | FIXED (MED-3) |
| D3 | limb processing | `organ.dm:476`, `organ_external.dm:357-380` | Reattached limbs stay on SSobj as well as `process_organs`: wounds and germs run at double speed. | serious | CLOCK | FIXED |
| D4 | sabotage | `organ_external.dm:1503-1515` | Emagged-limb explosion runs after `owner = null`; `qdel(src)` inside `removed()` while `droplimb()` continues. | serious | OWN | FIXED (MED-7): explosion/sparks use `victim`; the limb is deleted via `om_qdel_after(src, 1)` after droplimb() unwinds. |
| D5 | implants | `organ_external.dm:1469-1476, 1439-1454`, `cavity.dm:143-146` | Raw `implant.loc =` on removal; `imp_in`/`part`/`implanted`/embedded verbs never cleared. | serious | OWN | FIXED |
| D6 | amputation | `surgery/limbs.dm:3-36` | Amputation needs no depth and no real confirmation. | critical | CRIT | FIXED |
| D7 | scanner | `bodyscanner/data.dm:191` | `I.status & ORGAN_ASSISTED` tests a robotic level against the status bitfield. | serious | FIX: `I.robotic == ORGAN_ASSISTED`. | FIXED (MED-3) |
| D8 | book | `surgery/procedures.dm:243-260, 320-340` | Retinal repair and necrotic resection lack saw/pry steps, so the step is never offered on encased limbs. | serious | FIX: add the access steps; extend the test to simulate reachable depth. | FIXED (MED-3) |
| D9 | trends | `diagnose.dm:100-102`, `bodyscanner/data.dm:32` | Every `diagnose()` overwrites `last_scanned_severity`; scanner trends always read stable. | serious | FIX: baseline per device, updated on explicit scans. | FIXED (MED-3) |
| D10 | defib window | `internal/brain.dm:36-43`, `defib.dm:523`, `human_attackhand.dm:629`, `scanners/health.dm:2` | `defib_timer` units are wrong (about 100 min, not 10); CPR, defib and analyzer disagree; ticked by both `process()` and the `defib_timer` life system. | serious | CLOCK | FIXED (MED-7): brain `defib_elapsed` charged on the body clock by `sync_defib_window()` (death, revival, removal, insertion, reads); one `defib_window_left()` / `revival_brain_damage()` for revival, defib, CPR and the analyzer (`revival_window_left()`); full config minutes; the defib_timer Life stage and brain tick are gone. |
| D11 | defib | `defib.dm:251-309` | `can_revive` never checks a missing heart. | serious | FIX: refuse with "no cardiac activity" when the heart is required and missing. (Revive dup: P2-D1.) | FIXED (MED-3) |
| D12 | bench dissection | `organ_external.dm:244-293` | Raw `loc =` moves of children, organs and tourniquet; `children` not updated; bioregen leaves necrosis afflictions. | serious | OWN | FIXED (MED-7): moves already go through forceMove and the ledger's link/unlink hooks keep `children`; bioregen now removes the limb's tissue_necrosis (`clear_necrosis()`). |
| D13 | rejuvenate | `organ_external.dm:692` | `owner.has_embedded_objects()` before the `if(owner)` check. | serious | FIX: `owner?.`. | FIXED (MED-2) |
| D14 | EMP | `organ_external.dm:433, 487` | `owner.loc`/`owner.shock_stage` after an `owner?` guard; detached prosthetic EMP runtimes. | serious | FIX: guard both. | FIXED (MED-2) |
| D15a | tourniquet | `stabilisation/tourniquet.dm:84-104`, `organ_external.dm:116-118` | Nothing clears `E.tourniquet` when the tourniquet is deleted or moved; the limb stays occluded forever. | serious | OWN | FIXED (MED-7): limb `Exited()` and tourniquet `Destroy()` clear `E.tourniquet` (`release_lost_tourniquet()`). |
| D15b | tourniquet | same | Ischemia only on the cinched limb although `flow_occluded()` covers distal limbs. | serious | FIX: afflict ischemia on every occluded limb, or have ischemia read `flow_occluded()`. | FIXED (MED-2) |
| D16 | surgery | `surgery/surgery.dm:414-431` | On `do_after` failure, `complicate()` runs on a possibly deleted target; interruption always counts as a complication. | serious | FIX: validate first; skip complications on interruption. | FIXED (MED-2) |
| D17 | bleeding | `organ_external.dm:984-987` | `bleed_timer--` on every `update_damages()` call. | serious | CLOCK | FIXED (MED-7): `run_bleed_clock()` charges bleed_timer by CLOCK_BIO time elapsed while bleeding, in life cycles. |
| D18a | bleeding | `organs/blood.dm:210-226` | Internal bleeding checks reagent IDs directly. | debt | EXPO | STILL OPEN |
| D18b | bleeding | `organs/blood.dm:197` | +2 bleed for any open limb even with a clamped incision. | serious | FIX: take incision bleeding from `incision.is_bleeding()`. | FIXED (MED-3) |
| D19 | scanner | `bodyscanner/data.dm:132-209` | Scanner per-organ data bypasses `diagnose()`: raw `germ_level`, fake-death constants, ignores profile. | debt | FIX: fold into `diagnose_parts` findings; delete these emitters. | STILL OPEN |
| D20 | organ owner | `organ.dm:162-163, 686-688` | `process()` silently nulls `owner` when displaced; `check_verb_compatability` derefs a missing parent. | serious | OWN | FIXED (MED-7): the owner-nulling in process() was already gone; `check_verb_compatability()` returns FALSE with no parent limb. |
| D21 | nymph | `surgery/organs.dm:228-243` | `target.species = GLOB.all_species[SPECIES_DIONA]` bypasses `set_species()`. | serious | FIX: go through `set_species()` and `body.invalidate()`. | FIXED (MED-3) |
| D22 | pain | `organs/pain.dm:79-84, 106-108` | `maxdam` scaled inside the loop; fractional values miss the switch; `parent.name` unchecked. | serious | FIX: scale after the loop; `round()`; guard `parent`. | FIXED (MED-3) |
| D23 | limbs | `organ_external.dm:403-583, 1040-1174, 1333-1411` | `apply_wound_damage` god proc (180 lines) with `spawn()` on children; `robotize` nanoform hack; magic numbers. | debt | FIX: split spillover/wounding/dismemberment; replace `spawn` with `QDELETED`-checked calls; name constants. | STILL OPEN |
| D24 | perf | `human_organs.dm:8-17, 45-76` | Every tick walks all organs and limbs; each bad limb calls `get_wounds()` about 6 times. | perf | CLOCK | STILL OPEN (MED-7 partial): process_organs walks each limb's wounds once per cycle; the per-tick full-limb walk in `recheck_bad_external_organs()` and the ~6 `get_wounds()` calls inside limb helpers remain (needs a cached per-limb wound view). |
| D25 | debt | `organ.dm:124`, `blood.dm:49, 417`, `defib.dm:234-237, 267`, `subtypes/replicant.dm:64-75, 165-225`, `machine.dm:30` vs `organ.dm:680` | `isSynthetic()` branching; replicant `/crew` organs copy parents; robot heat written twice (0.5 vs 0.25). | debt | W6 | STILL OPEN |

---

# Part 2: duplication, scattered checks, coupling, bad functions

IDs: **P2-D** duplication, **P2-S** scattered checks, **P2-K** coupling, **P2-F** bad functions.
Counts come from Grep over the whole `code/` tree unless stated.

## Duplication

| ID | Locations | Problem | Dest | Status 2026-09-27 |
|---|---|---|---|---|
| P2-D1 | `defib.dm:490-503`, `human_attackhand.dm:611-620`, `vorepanel.dm:1236-1244, 1327-1335`, `medicalmods.dm:85-92`, `gloves/antagonist.dm:132-135`, `horror.dm:582-585`, `robot_upgrades.dm:96-99`, `organs/subtypes/machine.dm:89-92`, `brain/brain.dm:71-76`, `MMI.dm:217-219, 246`, `living.dm:457-464`, `changeling/powers/revive.dm:34-36`, `technomancer/spells/resurrect.dm:36-38, 56-58`, `xenoarcheaology/effects/resurrect.dm:78-80, 101-103`, `soulcatcher.dm:139`, `nifsoft/13_soulcatcher.dm:239`, `ai.dm:1029, 1043` | **~20 hand-rolled revives** (list swap + `timeofdeath = 0` + `set_stat` + `failed_last_breath` + `reload_fullscreen`), each with a slightly different subset. Several copy the same `WARNING("...already in the living or dead list")`. | OWN (`return_from_death()`; lint on `GLOB.dead_mob_list -=` outside it) | FIXED |
| P2-D2 | `vorepanel.dm:1221-1234, 1314-1325`, `defib.dm:251-287`, `human_attackhand.dm:629-631`, `human.dm:1682-1697` (`check_vital_organs`) | Revive eligibility (brain timer + vital organs) is written four times. Vorepanel uses `O.damage > O.max_damage` where `check_vital_organs` uses `>=` and checks brain death, so the vore path revives bodies the defib refuses. | OWN (`can_return_from_death()` next to `return_from_death()`) | FIXED |
| P2-D3 | `mob/death.dm:3-79` | `gib()`, `dust()` and `ash()` are the same body three times, each with `spawn(15) qdel`. | FIX: one `/mob/proc/disintegrate(anim, remains, gibs)` using `QDEL_IN`. | STILL OPEN |
| P2-D4 | `mob/living/death.dm:1-36`, `projectiles/targeting/targeting_mob.dm:25`, `freelook/mask/update_triggers.dm:32`, `mob/death.dm:81-84` | `/mob/living/death()` is defined three times in three files. The main one runs nest removal, soul-link callbacks, `vore_death` and the death sound **before** calling `..()`, where the `stat == DEAD` guard lives. A second `death()` call (A6, A8) repeats all of them. | FIX: guard `if(stat == DEAD) return FALSE` first; turn the targeting and cultnet overrides into `COMSIG_MOB_DEATH` listeners. | FIXED |
| P2-D5 | `medical/conditions/pharmacology/*.dm` (about 40 `overdose/*/get_stages()`, e.g. `tissue_repair.dm:17-181`, `organ_repair.dm:17-260`, `detoxifiers.dm:59-231`) | Every overdose affliction hand-writes a near-identical stage table differing in numbers and symptom lists. | EXPO (overdose as data on the reagent) | STILL OPEN |
| P2-D6 | `medicine.dm:820-923` | Respirodaxon, gastirodaxon, hepanephrodaxon and cordradaxon share one body: loop organs, skip robotic, filter by an organ list literal, confuse, then check two "partner" reagents. Only the organ list, partners and side effect differ. | EXPO (organ targets and interactions as data) | STILL OPEN |
| P2-D7 | `species/station/station.dm:681-710` (diona), `alraune.dm:211-218`, `datums/components/traits/photosynth.dm`, `burninlight.dm` | Light-driven nutrition and healing is implemented at least three times with different thresholds and treatment tags. | W6 (one photosynthesis trait/gene the species grant) | STILL OPEN |
| P2-D8 | `alraune.dm:103-305` | A 200-line self-described "crude copypasta of handle_breath" for skin breathing. | W6 (breath profile: CO2-in, skin route) | STILL OPEN |
| P2-D9 | `organs/subtypes/machine.dm:65-71` vs `internal/brain.dm:36, 143`; callers `lungs.dm:34-37`, `human/life.dm:2069, 2344` | `mmi_holder` is not a brain but duck-types `tick_defib_timer()` (no-op) and `get_control_efficiency()` so callers can treat whatever sits in `O_BRAIN` as a brain. | OWN (a brain-slot interface on the organ hierarchy) | FIXED (MED-7): `get_control_efficiency()` lives on `/obj/item/organ/internal` (the brain-slot interface); callers type the slot as internal organ; mmi_holder's duplicate and the cell's fake `defib_timer` removed. |
| P2-D10 | `silicon/robot/life.dm:273-297`, `brain/life.dm:145-168`, `human/life.dm` health icons, `_helpers/mobs.dm:132` (`vitality_hud_state`) | The vitality → `health0..7` band table is written at least three times with different cut points (robot: 0.875/0.75/…, brain: 80/60/…). | FIX: all HUDs call `vitality_hud_state()`. | STILL OPEN |
| P2-D11 | `robot.dm:255-275` (`rejuvenate`), `living.dm:420-476` | Robot rejuvenate rebuilds parts and then calls the base, which clears `radiation`, `nutrition = 400`, `bodytemperature = T20C` on a borg. | OWN (revive path per body plan) | FIXED (MED-7): base rejuvenate calls `rejuvenate_physiology()`; robots override it to a no-op. |
| P2-D12 | `organs/subtypes/standard.dm:30-35`, `species.dm:515`, `nanoform.dm:175`, `internal/brain.dm:85`, `implantaugment.dm:42, 86`, `surgery/organs.dm:188, 231`, `protean_powers.dm:284`, `vorepanel.dm:1298` | **~11 sites** outside `organ.dm`/`organ_external.dm` write `internal_organs_by_name[...]`/`organs_by_name[...]` directly instead of going through `replaced()`. | OWN | FIXED |

## Scattered checks

| ID | Question | Sites | Problem | Proposed predicate | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|---|
| P2-S1 | "Is this mob synthetic?" | **217 calls in 113 files** to `isSynthetic()`; overrides in `human_helpers.dm:110`, `brain.dm:97`, `bot.dm:522`, `mob_helpers.dm:35`, `corrupt_hounds.dm:93, 336`, `mechanical.dm:25` | Human `isSynthetic()` returns a `/datum/robolimb` (used as data in `species_getters.dm:67, 75`, `update_icons.dm:1271, 1327`). Simple mobs declare `biology = BIOLOGY_SYNTHETIC` and also override `isSynthetic()`, two sources of truth. The brain view is "synthetic" when its loc is an MMI. | `L.biology()` (systemic, from the body) and `body.biology_of(part)`; `robolimb_model()` for the cosmetic use. | W6 | STILL OPEN |
| P2-S2 | "Is this part robotic?" | **145 raw `robotic >=/</== ORGAN_*` comparisons in 63 files** (26 in `organ_external.dm`, 10 in `organ.dm`, 10 in `medicine.dm`) | Mixed thresholds (`>= ORGAN_ROBOT` vs `>= ORGAN_ASSISTED`) answer different questions under the same idea. D7 is one of the resulting bugs. | `/obj/item/organ/proc/is_robotic()` / `is_assisted()`, or `body.biology_of(part)` for treatment. | W6 | STILL OPEN |
| P2-S3 | "Is this mob mechanical?" | `mob.dm:742-745` | A third predicate, `is_mechanical()`, is never called and compares `get_species()` to the string `"Machine"`, which no species uses. | Delete. | FIX | STILL OPEN |
| P2-S4 | "Can this mob feel pain?" | `can_feel_pain()` at `living.dm:870`, `carbon.dm:436`, `human.dm:1699`; direct `NO_PAIN` reads at `human/life.dm:1722, 1740`, `mob_grab_specials.dm:131`, `organ.dm:638`, `fryer.dm:232` | Five sites bypass the predicate (and so ignore `BF_PAIN_IMMUNITY`, synthetic and belly rules). | `can_feel_pain()` everywhere; `NO_PAIN` becomes a species grant feeding `BF_PAIN_IMMUNITY`. | W6 | STILL OPEN |
| P2-S5 | "Which species is this?" | **31 `species.name ==`/`get_species() in` comparisons in 23 files, plus ~20 `istype(H.species, /datum/species/X)`** e.g. `malignant.dm:63-66`, `bodyscanner/data.dm:53` and `human/life.dm:1614` (the same custom/hanner nutrition check twice), `bellymodes.dm:367`, `xenobio/items/weapons.dm:25, 95`, `extracts.dm:238, 860`, `cyborg.dm:566` (promethean ×5), `teshari.dm:10, 23`, `holder_micro.dm:16, 32` | Species identity is used as a stand-in for a property (slime-bodied, can't host malignancy, carries micro, alternate hunger icons). | Species facts/grants: `is_slime_bodied`, `can_host_malignant`, `hunger_alert_style`, `micro_carry`. | W6 | STILL OPEN |
| P2-S6 | "Is it in stasis?" | `inStasisNow()` at ~17 sites (`human/life.dm:185, 307, 367, 1250, 1868`, `simple_mob/life.dm:207`, `blood.dm:61`, `station.dm:682`, `alraune.dm:104`, 4 trait components, `combat_ai/.../interfaces.dm:69`); `ctx.in_stasis()` at `human/life.dm:125`, `physiology.dm:504` | One flag, two read APIs, and every system polls it each tick to skip work. | Stasis as a paused body clock: systems read time from the clock and don't need to ask. | CLOCK | STILL OPEN (MED-7 note): both APIs read the one `body.stasis_paused` flag set by `advance_stasis()`; moving the ~17 sites to read elapsed CLOCK_BIO time (so they need not ask) is a larger per-system rewrite. |
| P2-S7 | "Does it breathe?" | **49 matches in 23 files** for `NO_BREATHE` / `does_not_breathe` / `should_have_organ(O_LUNGS)` / `breath_type` | Emotes, gear dispensers, resleeving, vitals, physiology and species each decide separately. | Breath profile on the body: `breathes()`, `breath_profile()`. | W6 | STILL OPEN |
| P2-S8 | "Is it alive / down / critical?" | `is_critical()` 33 uses; raw `vitality() <=/</>= N` **46 uses in 32 files** with thresholds 0, 0.33, 0.5 and more; `mob.is_dead()` (stat) vs `body.is_dead()` (lethal damage) | Same word, different meanings: `body.is_dead()` means "damage is lethal", `mob.is_dead()` means `stat == DEAD`, and `human_attackhand.dm:583` needs both. AI flee, bellies, bosses and HUDs each invent a threshold. | Rename `body.is_dead()` to `is_lethal()`; add named bands (`VITALITY_BAND_*`) and `L.vital_band()`. | NEW:VITALS | FIXED |
| P2-S9 | "Can it be injected?" | `can_inject()` 29 call sites, ~20 simple-mob overrides; `syringes.dm:241-250` skips it for humans; `hypospray.dm:40-67` never calls it | Armour and thick skin are honoured by some injectors and not others. | One `can_inject(user, zone, method)` called by every injector (method = needle / hypo / spray). | EXPO (injection is a route) | STILL OPEN |
| P2-S10 | Body temperature writes | **92 raw `bodytemperature +=/-=/=` writes in 41 files** (21 in `food_drinks.dm`, 9 in `human/life.dm`, afflictions, symptoms, organs, heatsinks) | No single writer, no scaling by time or dose, fights thermoregulation (B12, B15, C16). | `L.adjust_body_heat(joules, source)`, one writer; afflictions contribute `BF_TEMPERATURE`. | NEW:HEAT | STILL OPEN |
| P2-S11 | Nutrition writes | **124 raw `nutrition +=/-=/=` writes in 52 files** (25 in `station_special_abilities.dm`, 16 in `food_drinks.dm`, vore `digest_act.dm:141, 235`, `belly_obj.dm:1217`, `bellymodes.dm:401`) vs `adjust_nutrition()` | Bypasses the clamp in `adjust_nutrition()` (`living.dm:1100`) and any hunger model. | `adjust_nutrition()` only. | W6 | STILL OPEN |
| P2-S12 | Radiation writes | **91 raw `radiation`/`accumulated_rads` writes in 35 files** (16 in `human/life.dm`, 13 in `radiation_effects.dm`, 10 in reagents) | Healing and dosing bypass the radiation model (B14). | Radiation as an exposure. | EXPO | STILL OPEN |
| P2-S13 | Species gates in reagents | **187 `alien == IS_*` branches in 11 reagent files** (62 in `food_drinks.dm`, 61 in `medicine.dm`, 38 in `toxins.dm`) | Every reagent re-decides who it affects; B2 happens because tags and factors don't see these gates. | One `effective_dose(owner)` with the species/biology gate. | EXPO | STILL OPEN |
| P2-S14 | Shock stage | 18 direct `shock_stage` writes in 7 files (`station.dm:695, 709`, `modifiers_misc.dm` ×4, `organ_external.dm` ×3) | Species and modifiers poke the shock counter directly. | `adjust_shock(amount, source)` owned by the shock system. | W6 | STILL OPEN |

## Coupling

| ID | Location | Problem | Dest | Status 2026-09-27 |
|---|---|---|---|---|
| P2-K1 | `vore/eating/vorepanel.dm:1206-1336` | Belly "reform" code mends the body, reimplements revive eligibility (P2-D2), swaps life lists, does raw `MMI.loc = R` / `MMI.loc = holder`, writes `internal_organs_by_name[O_BRAIN]` and calls `holder.update_from_mmi()` (which itself hand-revives, A20). Vore is editing body, organ and mind-host state directly. | OWN | FIXED (MED-7): reform already used `reform_restore()`/`revive()` and forceMove; the hand-built MMI holder (which leaked a fresh MMI) is replaced by `install_mmi_holder()`, shared with the surgery step; the holder now moves an installed MMI into itself. |
| P2-K2 | `mob/death.dm:86-98`, `mob/living/death.dm:19-22`, `human.dm:1702-1708` | The core death proc knows about borers, bellies, dogborg sleepers, shoes and `tf_mob_holder` to pick a deathmessage. `can_feel_pain()` reads a belly's `digest_mode`. | FIX: bellies/containers answer a `COMSIG_MOB_DEATH_MESSAGE` / pain-suppression signal; the core asks, not knows. | STILL OPEN |
| P2-K3 | `species.dm:615` `environment_effects()` and its 7 species overrides (`alraune.dm:103`, `station.dm:681, 1582, 1739, 1984`, `alien_species.dm:116`, `greyYW.dm:73`, `custom.dm:92`, `avatar.dm:45`) plus 7 trait overrides | Species datums run per-tick life logic that writes `nutrition`, `shock_stage`, `failed_last_breath`, body breath quality, and calls `mend()`/`injure()` (70 `H.<body var>` hits across 10 species files). | W6 | STILL OPEN |
| P2-K4 | `game/machinery/medical_kiosk.dm:125-149` | The kiosk reads `germ_level` and `isSynthetic()` directly instead of a diagnosis profile (same class as D19). | FIX: use `diagnose()` with a kiosk profile. | STILL OPEN |
| P2-K5 | reagents: 66 direct writes in 7 files to `damage`, `germ_level`, fractures, wounds, `bodytemperature`, `radiation`, `pulse`, `nutrition` | Reagents reach into organs and mob vars instead of producing effects. | EXPO | STILL OPEN |
| P2-K6 | `medicine.dm:828, 859, 889, 921` and other `M.reagents.has_reagent(...)` partner checks | Reagents query each other to implement interactions. | EXPO (interaction table) | STILL OPEN |
| P2-K7 | `xenoarcheaology/effects/resurrect.dm:78, 101` | Writes `SM.stat = CONSCIOUS` / `L.stat = CONSCIOUS` directly, skipping `set_stat()` (no sight, HUD, wake or signal). This is a live bug, not only coupling. | OWN (and a lint on raw `stat =` writes) | FIXED |
| P2-K8 | `unit_tests/dq_medical_tests.dm`, `dq_surgery_tests.dm`, `dq_bodyscanner_tests.dm` (~35 `C.severity = N`) | Tests write affliction `severity` directly, so they don't exercise `set_severity()` invalidation and can pass on states the game can't reach. | FIX: use `set_severity()` in tests. | STILL OPEN |

## Bad functions

| ID | Location | Category | Problem | Dest | Status 2026-09-27 |
|---|---|---|---|---|---|
| P2-F1 | `human/life.dm:613` breathing `exchange` (290 lines), `950` environment `exchange` (179), `1312` `update_status` (187), `1509` HUD `tick` (182), `2148` `hud_list` (163), `363` radiation (164) | god procs | Human life's big six. | W6 | STILL OPEN |
| P2-F2 | `human/examine.dm:1` (458 lines), `human.dm:413` `Topic` (374), `human.dm:1929` `vv_do_topic` (204), `update_icons.dm:175` `update_icons_body` (205) | god procs | Human UI/admin procs that also read body internals directly. | FIX: split by section; examine reads findings from diagnosis. | STILL OPEN |
| P2-F3 | `resleeving/autoresleever.dm:69` (193), `resleeving/computers.dm:241` `tgui_act` (253) | god procs | Resleeving flow and UI in single procs. | FIX: split. | STILL OPEN |
| P2-F4 | `vore/eating/bellymodes.dm:4` `belly_cycle` (182), `vore/eating/living.dm:1409` `vore_transfer_reagents` (181), `vorepanel.dm:1026` `pick_from_outside` (379, contains P2-K1) | god procs | Vore procs that do body work inline. | FIX (split); the body parts go to OWN via P2-K1 | STILL OPEN |
| P2-F5 | `silicon/robot/dogborg/dog_sleeper.dm:454` `clean_cycle` (157) | god proc | Machine-occupant digestion/cleaning in one proc. | C8B | STILL OPEN |
| P2-F6 | `human_helpers.dm:365` `transform_into_other_human(character, copy_name, copy_flavour, convert_to_prosthetics, apply_bloodtype)` | boolean flags | Four boolean switches on one 156-line proc. | FIX: an options datum or separate procs. | STILL OPEN |
| P2-F7 | `damage_procs.dm:4` `apply_effect(..., check_protection)` | misleading / dead param | `check_protection` is never read; `IRRADIATE` always applies armour. Callers pass `check_protection = 0` expecting it to skip armour. | FIX: honour it or remove it. | FIXED (MED-3) |
| P2-F8 | `food_drinks.dm:3361` (vodka), `4873` (godka) | bug found in passing | `apply_effect(max(M.radiation - k*removed, 0), IRRADIATE)` **adds** the drinker's current radiation back every tick, roughly doubling it, when the intent was to reduce it. | FIX now: reduce radiation (later EXPO). Serious. | FIXED (MED-2) |
| P2-F9 | `alraune.dm:300-302` | bug found in passing | `get_environment_discomfort(src, "heat")` passes the species datum, not `H`. `alraune.dm:120` also reads `H.loc.return_air()` without a loc check. | FIX | FIXED (MED-3) |
| P2-F10 | `mob.dm:742` `is_mechanical()`, `factors.dm:259` `COMSIG_LIVING_FACTORS_CHANGED`, `machine.dm:65` `mmi_holder/tick_defib_timer()` (no-op), Hannoa unreachable branches (`medicine.dm:1673-1678`) | dead code | Never called, never listened to, or unreachable. | FIX: delete (Hannoa via B7). | STILL OPEN |
| P2-F11 | **326 commented-out code lines in 102 files** in the audited areas; worst: `species/station/station.dm` (30), `simple_mob/.../shadekin/types.dm` (26), `food_drinks.dm` (18), `robot/sprites/.../gooborgs.dm` (16), `drone/drone_items.dm` (10), `synx.dm` (10), `distilling.dm` (9), `bigclowns.dm` (9), `human.dm` (8), `syringes.dm:227-231` and `hypospray.dm:47-51` ("preserved for posterity") | commented-out code | Git history is the record (AGENTS.md). | FIX: delete in a sweep. | STILL OPEN |
| P2-F12 | `body/body.dm:409` `is_dead()` vs `mob.dm:739` `is_dead()`; `human_helpers.dm:110` `isSynthetic()` returning a robolimb | misleading names | See P2-S1, P2-S8. | NEW:VITALS / W6 | STILL OPEN |

---

# Summary

## Counts per destination

| Dest | Part 1 | Part 2 | Total |
|---|---|---|---|
| CRIT | 10 | 0 | 10 |
| CLOCK | 5 | 1 | 6 |
| OWN | 7 | 7 | 14 |
| NULL | 2 | 0 | 2 |
| EXPO | 7 | 7 | 14 |
| W6 | 4 | 11 | 15 |
| C8B | 0 | 1 | 1 |
| NEW:HEAT | 2 | 1 | 3 |
| NEW:VITALS | 0 | 2 | 2 |
| FIX | 64 | 16 | 80 |
| INVALID | 0 | 0 | 0 |
| **Rows** | **101** | **46** | **147** |

Part 1 has 101 rows because D15 and D18 were each split into a framework half and a FIX
half. Part 2 FIX rows include P2-F4, whose body-editing part goes to OWN through P2-K1.

## FIX list, prioritised

**P0: lost state, runaway state, soft-locks**
1. C1: thermal runaway can't be treated on cyborgs (permanent unconsciousness).
2. P2-F8: vodka/godka roughly double radiation every tick.
3. P2-D4: guard `/mob/living/death()` before its side effects. This fixes double soul-link, nest and sound calls, and the A8 double loot.
4. A10: the mind's blank identity overwrites the body's (lost traits such as `no_clone`).
5. D15b, D16, D13, D14, A7: runtimes and wrong targets in tourniquet, surgery and limb code.

**P1: wrong medical results**
6. B10 addiction chain; B9 trauma kit charges; B20 burn kit on open limbs; B22 syringe `can_inject` and negative stab.
7. B5 claridyl; B7 Hannoa; B8 Eden; B16 Malish-Qualem; B21 Talum-quem; B23 Lipostipo.
8. B3/B17 blood compatibility; B11 iron; B18 double nutriment; B19 species factor merge; B12 cold-drink sign.
9. C4/D2 untargeted decompression; C5 bruising; C2/C3 simple-body venom and hypoxia; C6 dispatcher overwrites treatment; C7, C8, C9, C14, C15, C17, C21, C22, C23.
10. D7 scanner "Assisted" label; D8 surgery book steps; D9 scanner trends; D11 defib with no heart; D18b clamped incision bleed; D21 nymph species; D22 pain messages.
11. A5 orphan cells; A22 borg belly lights; P2-F9 alraune discomfort; P2-F7 `apply_effect` protection param.

**P2: performance**
12. A11, A13, A15, A12, A14, A17, A19; B24; C12, C13, C19, C20.

**P3: debt and cleanup**
13. P2-D3 gib/dust/ash; P2-D10 HUD bands; P2-K2 death/pain knowing about vore; P2-K4 kiosk; D19 scanner emitters; D23 `apply_wound_damage` split.
14. P2-F2, F3, F4, F6 splits; P2-S3 and P2-F10 dead code; P2-F11 commented-out code sweep; P2-K8 tests writing severity; C18; A21.

## New frameworks recommended

- **NEW:HEAT, a body heat ledger.** One writer for body temperature (`adjust_body_heat(joules, source)`), scaled by time and dose, with afflictions contributing `BF_TEMPERATURE` rather than writing. It removes the 92 raw writes (P2-S10) and bugs B12, B15 and C16, and gives thermoregulation one input. It could sit inside EXPO if EXPO is widened to "all exposures, including heat".
- **NEW:VITALS, a vital-state predicate set.** Named vitality bands (`vital_band()`), `is_lethal()` in place of `body.is_dead()`, and one `vitality_hud_state()`. It replaces 46 ad-hoc thresholds and the same-name/different-meaning `is_dead()` pair (P2-S8, P2-F12, P2-D10).
- **Death pipeline** (fold into OWN if preferred). One guarded `death()` that does core state, then `COMSIG_MOB_DEATH` listeners for targeting, cultnet, soul links, nests, bellies and deathmessage suppression. Pair it with the lint that already fits OWN: no `GLOB.dead_mob_list -=`, `GLOB.living_mob_list +=` or `stat =` outside `death()` and `return_from_death()`.
