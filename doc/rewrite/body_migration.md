# Body migration: one body system (track B)

Owner: `rewrite/body-full`. Goal: the body on the final API (`final_api.html` sections 3, 5, 9, 14): one body system,
wounds and conditions as stat sources and timed holds, healing and bleeding as rates over time, blood a resource,
organ function as contributions, surgery steps as ops, body heat on `code/domains/heat`, nothing polled per limb.
Life (`rewrite/om-life`) reads what the body owns; it does not compute it.

## 1. Inventory (October 2026)

| Area | Where | Shape today | Polled? |
|---|---|---|---|
| Body, plans, injure()/mend(), afflictions, treatment snapshot, physiology | `code/modules/body/` (~5k) | the newer rewrite; event-driven vitals (`body.dirty`) | `life_tick()` per Life cycle (afflictions) |
| Medical conditions, lesions, wounds, contagion, diagnosis | `code/modules/medical/` (~20k) | afflictions, data-driven | ticked by the body |
| Limb (external organ) | `code/modules/organs/organ_external.dm` (1.7k) | wounds are afflictions; autoheal `update_wounds()` per Life cycle with `wound_update_accuracy` "emulate realtime"; `need_process()`/`bad_external_organs` gate; `update_damages()` runs the bleed clock and fractures; germs `update_germs()`/`handle_germ_sync()`/`handle_germ_effects()` | yes: Life stage `organs` |
| Internal organs | `code/modules/organs/internal/*.dm` | `periodic_step()` per organ per Life cycle, `PROCESS_ACCURACY` tick counting (liver, kidneys, lungs, heart, eyes, spleen, appendix, horror, malignant), `life_step_idle()` | yes: Life stage `organs` |
| Germs / infection | `organ.dm` `handle_germ_effects()`/`handle_antibiotics()`/`handle_rejection()`, `medical/infection_bridge.dm` | a raw `germ_level` number, random increments per cycle, bridged into `wound_infection` | yes |
| Blood, bleeding | `code/modules/organs/blood.dm` | Life stage `blood/carbon/human`: regen +0.1/cycle, `caculate_bloodloss_and_bleed()` sums wound bleeds per cycle, pale/fatal collapse | yes: Life stage `blood` |
| Pain | `code/modules/organs/pain.dm` | Life stage `pain` picks the worst limb, messages | yes: Life stage `pain` |
| Surgery | `code/modules/surgery/` | data steps (`/datum/surgical_step`), `do_surgery()` attack-chain entry, `om_task_start` timed tasks, `surgery_ask` prompts | no |
| Body heat | `code/modules/heat/heat_mobs.dm` on `code/domains/heat` | landed (H2) | no |

## 2. Target model

- **Wounds.** A wound is an affliction with `damage`, a heal *rate* and a bleed *rate*. Nothing counts ticks. The
  body owns one wound clock per mob: `every(BODY_WOUND_STEP, ..., when = nameof(wound_activity))` on the human, where
  `wound_activity` is a tracked flag the body raises when a wound is added, opened, treated or closes and drops when
  no wound heals, bleeds or waits to fade. The step integrates rates over `A.dt` (the mob's own clock, so stasis
  stops it). Autoheal is `WOUND_AUTOHEAL_RATE` per second shared by the limb's wounds; bleeding is
  `damage / divisor` per second; an arterial bleed's tear grows at its own rate.
- **Blood.** The vessel is the store; `RES_BLOOD` is the resource ops spend. Regeneration and loss are rates applied
  by the same clock; pallor and the fatal collapse are thresholds read from the volume.
- **Limbs.** Integrity is the wounds' sum (already). Fracture is the `untreated_fracture` affliction (already); a
  splint is a hold on the limb's `fracture_held` stat; amputation, prosthetics and robolimbs keep their procs on the
  limb, called from injure() and surgery.
- **Internal organs.** Organ function is contributions: the heart contributes to circulation (`BF_PUMP`), the lungs to
  breathing (`BF_GAS_EXCHANGE`), the liver and kidneys to toxin clearance (`TREAT_ANTITOXIN` continuous source in
  the treatment snapshot), scaled by the organ's condition. Organ-specific periodic harm (toxin overload, withdrawal,
  coffee on bad kidneys) becomes rates in the body's organ clock.
- **Germs.** `germ_level` stays a number on wounds and organs, driven by rates (exposure, antibiotics as a negative
  rate) on the body clock, not random per-cycle increments; infection consequences stay `wound_infection`.
- **Pain.** Limb pain is already derived in the vitals; pain *messages* become an every() on the human gated by the
  body's `pain_messaging` flag.
- **Surgery.** Each `/datum/surgical_step` becomes an op on the human: tool affordance, `needs()` requirements over the
  limb state (depth, biology, coverage, something to treat), `wait(duration)`, `then(perform)`.

## 3. Slices

1. **Wounds and bleeding**: wound clock, autoheal and bleed rates, blood regeneration; the `organs` stage loses limb
   wound processing and the `blood` stage goes.
2. **External limbs**: fractures, splints, dislocation, amputation, prosthetics: `update_damages()` loses the bleed
   clock; `need_process()`/`bad_external_organs` go.
3. **Internal organs**: `periodic_step()` and `PROCESS_ACCURACY` go from every internal organ; function as
   contributions; organ harm as rates on the organ clock; `life_step_idle()` goes.
4. **Pain and germs**: pain stage to the body; germ rates; `handle_germ_*`/`handle_antibiotics()` go.
5. **Surgery**: steps as ops with needs()/req(); `do_surgery()` attack-chain entry and the om tasks go.
6. **Delete**: whatever of `code/modules/organs/` the slices emptied; the organ Life stage.

## 4. What dies

`update_wounds()`, `wound_update_accuracy`, `need_process()`, `last_dam`, `bad_external_organs`,
`recheck_bad_external_organs()`, `process_organs()`, `/datum/om/stage/life/organs`, `/datum/om/stage/life/blood/carbon/human`,
`caculate_bloodloss_and_bleed()`, `calculate_internal_bloodloss()`, `run_bleed_clock()`, `PROCESS_ACCURACY`, every
internal organ's `periodic_step()` and `life_step_idle()`, `handle_germ_sync()`, `update_germs()`,
`handle_germ_effects()`, `handle_antibiotics()`, `/datum/om/stage/life/pain`, `do_surgery()`'s task chain.

Behaviour changes are recorded in `intended_changes.md` under "Body migration".

## 5. Status

| Slice | State | What landed |
|---|---|---|
| 1 Wounds and bleeding | landed | body clock (`body_clock.dm`); Life `blood` stage, `update_wounds()`, bleed clock procs deleted |
| 2 External limbs | landed | stance/grip derived (`limb_state.dm`); `bad_external_organs`, `need_process()` deleted; deterministic splints |
| 3 Internal organs | landed | `organ_tick(cycles)` on the organ clock; Life `organs` stage, `process_organs()`, `PROCESS_ACCURACY` deleted |
| 4 Pain and germs | landed | germ rates; Life `pain` stage moved to the body (`pain.dm`) |
| 5 Surgery | landed | `surgery_ops.dm`; `do_surgery()`, the surgery om tasks and `surgery_ask()` deleted |
| 6 Delete / consolidate | landed | loose organs on a held stat; `code/modules/organs` moved to `code/modules/body/organs` |

Still legacy inside the organ types (owned by the framework waves, not this track): `OM_FIELD` organ state, `om_task` timed tasks
(robotic repair, butchery), `DECLARE_INTERACTIONS` on organs. The lifecycle-forms (`contains()`, declared lifetimes) apply to organ
setup and amputation once they land on master.
