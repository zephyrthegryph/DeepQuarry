# Mob Life and Processing Architecture

Review date: 2026-09-22. Companion to `doc/health_system_review.md`. Scope: how every
living mob is processed each cycle (`Life()`), whether that processing is event-driven,
how the big case-based procedures should be broken up, and the redesign of cyborgs,
drones, the AI, proteans and prometheans.

> **Scheduling superseded (2026-09-25).** Life no longer runs from SSmobs or a `Life()` proc:
> it runs on the object-model core, and wake bits became change channels. Sections 4.3,
> 4.8 and 4.9 describe the old scheduler; [rewrite/life_on_om.md](rewrite/life_on_om.md)
> is authoritative for when systems run, sleep and wake. The content model (systems,
> families, variants, gates, segments) described here still holds.

Method: three read-only review passes (life processing, cyborgs,
proteans/prometheans), then the serious claims re-checked by hand. Section 8 is a
single roadmap that replaces section 7 of the health review.

---

## 1. Summary

**Is mob processing event-driven? No.**
- Machinery is event-driven: it hibernates, subscribes to gas changes and versioned
  keys, and uses timers.
- Mobs are not. Every mob runs its full `Life()` every 2 seconds whether or not
  anything changed. The only skip is NPCs on z-levels with no players.
- A healthy, idle human costs roughly 500–800 proc calls per cycle, most of it
  recomputing things that have not changed:
  - internal organs: about 150
  - the player HUD: about 180, including a health doll drawn twice
  - the humanoid body recompute: about 95
  - repeated scans of all 11 limbs: about 130

**The shape of `Life()` is the root cause of the giant case procedures.**
- `/mob/living/Life` calls about 25 `handle_*` hooks in a fixed order. Carbon, human,
  species and component code override them.
- Robots, the AI and pAIs skip the parent and re-implement their own chains.
- Order and applicability are implicit in where `..()` sits and in type and species
  checks. That is how you get 150–300-line procedures with species branches inside.

**This pass found 12 more bugs** (section 3). Three are serious:
- Robots tick their body twice per cycle and reset their own unconsciousness.
- One EMP hits a cyborg two to four times.
- A protean or promethean in blob form has a completely frozen body.

**The design:** `Life()` becomes a scheduler over small composable **life systems**.
- Each system has one job, an explicit place in the order, and an explicit activation
  model: continuous, periodic, lazy or event.
- Systems go to sleep when they have nothing to do. A mob whose systems are all asleep
  leaves the subsystem until something wakes it, which is how machinery already works.
- Case logic becomes **strategies** (breathing organ, thermoregulation, form),
  **data tables** (gas effects, temperature bands, radiation tiers) and **providers**
  (examine, HUD, appearance).

**Cyborgs:**
- Components become real body parts with graded function that feeds body factors.
- Power and heat become the machine version of physiology, with one power ledger.
- The god procedures split.
- Dogborg features move into a component.

**Proteans and prometheans:** one character, one mob, many forms. The two-mob holder
pattern is the source of most of their bugs.

---

## 2. Is it event-driven today?

| Area | Model today | Event-driven? |
|---|---|---|
| Machinery | Hibernates (`PROCESS_KILL` or `hibernate_*`); `subscribe_gas_dependency` with change masks; versioned reactive keys; timers; `audit_reactive_sleepers` checks for missed wakes | yes |
| AI brains (`SSai`) | calm brains sleep | yes |
| TG status effects | exist and process only while active | yes |
| Mob `Life()` | life systems sleep by rule and wake on events; a mob with nothing awake hibernates out of `SSmobs` (§4.9). Humans, robots, the AI and pAIs still run most systems every 2 s until those systems get rules | partly |
| Body core | dirty flags, the emergent dirty domains and HUD dirty bits are incremental. But the humanoid `life_tick` always recomputes (`humanoid.dm:246`), the metrics domain compares values every tick, and every metabolised reagent triggers a full side-effect reconcile | partly |
| Stun, weaken, paralysis, sleep | counters; setters wake the statuses systems, which run only while a counter is live (§4.9) | partly |
| Robots | poll power draw per component, camera, radio, blindness, lights, HUD and lock countdowns every tick; rebuild the sprite every tick while unconscious or weapon-locked | **no** |
| Proteans and prometheans | poll injury load 2–12 times per tick, copy state between forms every tick, re-scan the turf to clean it every tick | **no** |

**How each piece of per-tick work should run** (continuous = every tick while active,
periodic = at a lower rate, lazy = computed on read, event = only when woken):

| Model | Work |
|---|---|
| Continuous while active | reagent metabolism; affliction progression; blood while bleeding or low; heat exchange outside the comfort band; radiation decay while above 0; physiology while not settled |
| Periodic | nutrition (every 5 cycles); darksight (every 2); AFK and ambience (every 15, clients only) |
| Lazy: deadlines or integrate-on-read | status durations; modifier expiry; robot killswitch and weapon-lock countdowns; AI backup charge |
| Event-driven | vision; voice and visible name; HUD; movement state, gravity, falling and pulling; mutations and disabilities; organs (active set only); breathing in unchanging air; heat inside the comfort band; pressure; robot power demand; robot camera, radio and lights; protean regeneration; promethean cleaning |

---

## 3. Bugs found in this pass

Numbered after the seven in the health review.

| # | Bug | Where | Effect |
|---|---|---|---|
| 8 | Robots tick their body twice per cycle and reset `stat` | `robot/life.dm:71`, then `..()` at `:153` → `living/life.dm:136-138` | Afflictions progress at double speed. A stunned or unpowered robot is set unconscious, then conscious, every tick, so it never stays down. `COMSIG_MOB_STATCHANGE` fires twice per tick, which spams belly owners. |
| 9 | One EMP hits a robot 2–4 times (predates the migration) | `robot_damage.dm:60, :64` and `living_defense.dm:162, :173` each call `..()` twice | Electric injury and confusion twice; cell drained and wires pulsed four times; EMP-blocking components checked only after the first pass. |
| 10 | Blob form freezes the character's body | human moved to nullspace (`protean_blob.dm:467`, `prommie_blob.dm:392`); `SSmobs` skips it and `living/life.dm:12` returns at `if(!loc)` | While blobbed: no affliction progression, bleeding or healing; reagents don't act; stuns forwarded to the human never wear off; injury can't knock the blob out. |
| 11 | The protean steel modifier revives dead organs and repairs surgery-only lesions, on anyone wearing it | `protean_species.dm:407-427`; also given to organic rig hosts (`rig/modules/protean.dm:167`) | Direct limb heals, `LESION_HEAL_ALL`, and `ORGAN_DEAD` cleared every tick. |
| 12 | Breathing cadence is tied to the atmos subsystem's counter | `carbon/breathe.dm:5` (`SSair.times_fired % 4 == 2`) | `SSair` now fires every 0.1–0.5 s depending on atmos load, so breaths come irregularly and depend on atmos activity instead of every fourth cycle. |
| 13 | The robot sprite is rebuilt every tick while unconscious or weapon-locked | `robot/life.dm:138-139, :340-341` → `uneq_all()` → `update_icon()`; the dogborg sleeper redraws on every SSobj fire (`dog_sleeper.dm:628-629`) | Wasted redraws and appearance churn. |
| 14 | Robot power has no single ledger | direct `cell.charge` writes: `dog_sleeper.dm:235-239` (no null check, can go negative), `dog_modules.dm:195-229` (no cap), `robot.dm:1560-1562`; three spend procs with different units (`robot.dm:1236-1272`) | Negative or over-full cells; inconsistent drain. |
| 15 | Reinserting a robot cell, or prying out a destroyed part, erases component damage | `robot.dm:743-744, :931, :707-716` | Free repairs. |
| 16 | The blob's `Destroy` leaves dangling references | `protean_blob.dm:167-174` doesn't clear `humanform.temporary_form`, the soul gem owner, belly owners or the rig's `myprotean` | The human's powers act on a deleted mob; hard-delete risk. |
| 17 | The health doll is drawn twice per cycle for players | `human/life.dm:1531-1570` duplicates `handle_hud_icons_health` (`:1665-1716`), and both run through `..()` (`living/life.dm:249`) | About 60 wasted calls per player per cycle. |
| 18 | The side-effect reconcile runs once per metabolised reagent per cycle | `reagents/holder/holder.dm:194-198` → `medical/emergent.dm:25-28` | Cost multiplies with the number of reagents in the blood. |
| 19 | Protean and promethean latent bugs | see list below | Various; small. |

Bug 19 covers:
- `check_if_valid` keeps using a null refactory after `expire()` (`protean_species.dm:344-348`).
- Two comparisons that are always false (`protean_blob.dm:412, :524`).
- Empty `spawn()` delays that delay nothing (`protean_powers.dm:333, 764, 768`).
- Promethean regeneration strain never rises (`prometheans.dm:298`).
- Dullahan import checks the wrong field (`protean_powers.dm:665`).
- The reconstitutor can leave `processing_revive` stuck on (`protean_reconstitutor.dm:186, 247-248`).

---

## 4. Design: life systems

### 4.1 Principles

1. **`Life()` is a scheduler, not a template method.** It runs a list of systems in an
   explicit order. No behaviour lives in `handle_*` overrides.
2. **One job per system, one writer per piece of state.** For example, only the body
   system sets consciousness, and only the status effects manage incapacitation.
3. **Composition, not inheritance.** Which systems a mob has comes from its body plan,
   species data, traits and components. It is computed once and shared.
4. **Every system says how it is activated and when it may sleep.** Continuous work is
   the exception and must justify itself.
5. **Variation is data or strategy**, never an if-ladder in shared code.
6. **Systems scale by elapsed seconds** (AGENTS.md §3e), so sleeping and waking never
   changes rates.

### 4.2 Types

```dm
/// One concern of a living mob's upkeep. A singleton per type (flyweight): per-mob
/// state lives on the mob, its body or a component, never on the system.
/datum/life_system
	var/name
	var/bit                      // LIFE_SYS_* flag, indexes /mob/living/var/life_awake
	var/phase = LIFE_PHASE_BODY  // INPUT → BODY → MIND → OUTPUT
	var/order = 0                // position within the phase
	var/period = 1               // run every Nth cycle while awake
	var/runs_when_dead = FALSE
	var/runs_in_stasis = FALSE

/// Does this mob get this system at all? Evaluated only when composing.
/datum/life_system/proc/applies(mob/living/L)
/// Register the signals, gas dependencies and timers that wake this system.
/datum/life_system/proc/attach(mob/living/L)
/datum/life_system/proc/detach(mob/living/L)
/// Do the work. Return LIFE_SLEEP when nothing is left to do until woken.
/datum/life_system/proc/process(mob/living/L, datum/life_context/C)
```

**`/datum/life_context`** is built lazily once per cycle. It holds elapsed seconds, the
environment (turf air, belly or none), the stasis factor and whether the mob is dead. It
replaces seven `inStasisNow()` calls and the repeated air lookups.

**Strategy singletons** handle anatomy variation. They are picked when the mob is
composed, from species and organs:
- `/datum/breath_strategy/lungs`, `/photosynthetic`, `/none`
- `/datum/thermo_strategy/endotherm`, `/ectotherm`, `/heatsink`, `/none`

### 4.3 Scheduling and hibernation

```dm
/mob/living
	var/list/life_systems   // shared ordered list for this composition; never mutated per mob
	var/life_awake = NONE   // systems that want to run
	var/life_cycle = 0

/mob/living/proc/wake(bits)          // O(1): set bits; if hibernating, rejoin SSmobs
/mob/living/proc/recompose_life()    // on species, body plan, organ set or trait change

/mob/living/Life(seconds)
	var/datum/life_context/C = life_context(seconds)
	life_cycle++
	for(var/datum/life_system/S as anything in life_systems)
		if(!(life_awake & S.bit) || (life_cycle % S.period))
			continue
		if(S.process(src, C) == LIFE_SLEEP)
			life_awake &= ~S.bit
	if(!life_awake)
		SSmobs.hibernate(src)
```

- **Composition cache.** `GLOB.life_system_sets[key]`, keyed by body plan + species +
  the flags that matter (breathes, has blood, …). Every human of a species shares one
  list; each mob holds a reference and a bitfield.
- **Hibernation, in three stages:**
  1. Systems sleep but mobs stay in `SSmobs`, so a quiet mob's `Life()` is nearly free.
  2. NPC and SSD mobs with nothing awake leave the run list.
  3. Players too, once HUD and client work are fully event-driven.
- **Missed-wake safety.** Every system has a unit test: change its input, assert the
  mob woke; hold it steady, assert the system sleeps. A debug audit modelled on
  `audit_reactive_sleepers` samples hibernating mobs and logs any system whose sleep
  condition no longer holds.
- **Profiling.** Extend `SSmobs`' existing per-type sampler (`MOB_PROFILE` log lines) to
  per-system cost, so every change is measured. Existing logging is kept.
- **The 14 `COMSIG_LIVING_LIFE` listeners** (species components and so on) become
  systems, so nothing assumes "`Life()` runs every 2 s".

### 4.4 Activation patterns

| Pattern | Use when | Mechanism | Examples |
|---|---|---|---|
| Continuous | coupled dynamics that change every tick while active | stays awake; sleeps on its own condition | metabolism, affliction progression, blood while bleeding, heat exchange away from equilibrium |
| Periodic | slow drift where exact timing doesn't matter | `period` | nutrition, darksight, AFK and ambience |
| Lazy | the value is a function of time since an event | store a deadline or integrate on read; a timer for the one moment that matters | status durations, modifier expiry, lock countdowns, AI backup charge |
| Event | nothing changes until something happens | wake bits from signals, gas dependencies, reactive keys, or explicit `wake()` at the write site | vision, identity, HUD, movement state, organs, breathing in steady air, robot power demand |

Three incremental data patterns are used inside systems:
- **Dirty flag, recompute on read**: body factors, vitals, sight, identity, the cached
  diagnosis.
- **Running totals kept at the write site**: limb trauma and burn totals, the active
  organ set, robot power demand.
- **Deadlines instead of countdowns.**

Existing infrastructure is reused:
- `subscribe_gas_dependency` (from machinery): a mob subscribes to the gas mixture it
  breathes and stands in, with a change mask derived from its comfort bands, and
  re-subscribes on `Moved`.
- `publish_reactive_dependency` keys for area and light changes.
- `/datum/status_effect` for incapacitation, and timers for deadlines.

### 4.5 The human system set

| Phase | System | Owns | Activation (sleeps when) | Woken by | Replaces |
|---|---|---|---|---|---|
| input | Breathing | breath source, breath quality, gas effects | continuous; sleeps when the breath source and its composition are unchanged and physiology is settled | `Moved`, internals or mask change, gas dependency on the breath source, physiology change | `handle_breathing`, `breathe`, `handle_breath` (306 lines), alraune breathing, lung-failure asphyxia |
| input | Thermal | heat exchange and self-regulation, temperature band | continuous away from equilibrium; event inside the comfort band | `Moved`, equipment, gas change, fever factor, fire | the temperature half of `handle_environment` (188), `stabilize_body_temperature`, the duplicated belly temperature ladder |
| input | Pressure | barotrauma | event (gas dependency with a pressure-band mask) | `Moved`, gas change, suit change | the pressure half of `handle_environment` |
| input | Radiation | dose decay; radiation affliction staged by dose | continuous while dose is above 0 | `irradiate()` | `handle_radiation` (158) |
| body | Metabolism | reagent processing, dose levels, reagent factors, one reconcile per cycle | continuous while any holder has reagents | reagent added | `handle_chemicals_in_body`; the per-reagent reconcile fan-out |
| body | Body | afflictions, factors, physiology, pain and shock, consciousness, death | continuous while there are afflictions or physiology is unsettled | `injure`, `mend`, `afflict`, factor dirty, support added | the always-recompute `life_tick`, `handle_shock`, `handle_pulse`, `handle_pain`, `dq_check_ischemic_damage`, the dirty medical domains |
| body | Blood | volume regeneration, bleeding | continuous while volume is low or bleeding | wound starts bleeding, blood removed | `handle_blood` |
| body | Organs | processing for the **active** organ set only | continuous while the set is not empty | germs rise, detach or transplant, lesion change, special organs (augments, malignant) | `handle_organs`, which processes every organ every tick |
| body | Nutrition | hunger, hydration, weight | periodic (5 cycles) | eating | nutrition inside `handle_chemicals_in_body`, `weightgain` |
| body | Genetics | mutation effects, disabilities, random events | event, with timers for random episodes | DNA change | `handle_mutations`, `handle_disabilities`, `handle_random_events` |
| mind | Status | stun, weaken, paralysis, sleep, jitter, … | none: status effects exist only while active (4.7) | setters | `handle_statuses` (9 procs every tick) |
| mind | Sleep | dreams, snoring, SSD sleep | continuous while asleep | `Sleeping()`, going SSD | parts of `handle_regular_status_updates` |
| mind | Addiction | cravings, withdrawal | continuous while addicted | addiction gained | `handle_addictions` |
| mind | Traits and species | shadekin energy, xenochimera feral, changeling chemicals, NIF, phobias | each its own system with its own activation | its own triggers | `handle_species_components`, the 14 `COMSIG_LIVING_LIFE` listeners, `handle_changeling`, `handle_nif`, `handle_phobias` |
| output | Senses | sight flags, darksight, hearing | event; darksight periodic (2) while the light level varies | equipment, `stat`, area, light | `handle_vision` (82), `handle_darksight` |
| output | Identity | voice, visible name | event | equipment, ID, mask, disguise | per-tick `GetVoice()` and `get_visible_name()` |
| output | HUD | player HUD elements | event: one dirty bit per element, raised by the system that owns the data | an owner's band changes | `handle_regular_hud_updates` (224), the duplicated `handle_hud_icons_health`, `handle_hud_list`, the 30-tick full refresh |
| output | Client | AFK marking, ambience | periodic (15), clients only | login | the AFK and ambience code in `Life()` |
| output | Movement state | canmove, gravity, falling, pulling, grabs | event | status change, `Moved`, grab | `update_canmove`, `update_gravity`, `fall`, `update_pulling` |

For a healthy, idle human in stable air, every system except Client is asleep. A cycle
costs a handful of bit tests instead of 500–800 calls. With hibernation on, it costs
nothing.

### 4.6 Breaking down the case-based procedures

**`handle_breath` (306 lines) becomes the Breathing system:**
1. `select_breath_source()`: internals, NIF spare breath, belly, turf, or vacuum.
2. `strategy.exchange(breath, species)`: returns breath quality and the exhaled gas.
3. `apply_gas_effects(breath)`: reads a data table of gas → partial-pressure bands →
   affliction trigger, factor or symptom. Phoron, N2O, CO2 and so on stop being
   `if` branches.
4. Breath temperature is handed to the Thermal system.
5. Feedback (gasps, alerts) is raised when a band changes.

Species breath data (`breath_type`, `poison_type`, `exhale_type`, thresholds) is read by
the strategy, with no species branches.

**`handle_environment` (188) plus `stabilize_body_temperature` becomes Thermal plus
Pressure.** Thermal has one `heat_exchange(environment, insulation)` and one
temperature-band table, used for normal and belly environments alike, so the duplicated
belly ladder disappears. Pressure raises barotrauma through triggers.

**`handle_radiation` (158) becomes the Radiation system**: dose decay, and a radiation
affliction staged from a tier table. It checks biology per part, so the seven
`isSynthetic` branches go away.

**`handle_regular_status_updates` (193) splits by owner:**
- consciousness → the Body system's output
- sleep → Sleep
- SSD → Client
- fear → the trait system
- eyes and ears → Senses
- drowsiness → Status

**`handle_regular_hud_updates` (224), `handle_hud_icons_health` and `handle_hud_list`
become the HUD system.**
- There is one element per dirty bit, raised by whichever system owns the data.
- The health doll reads the self-diagnosis once.
- Alerts (oxygen, temperature, pressure, nutrition) are thrown and cleared by the
  owning system when its band changes. The HUD never polls.

**`examine` (458) becomes ordered examine providers:**
- identity
- equipment
- vitals and findings from the glance diagnosis
- species
- vore
- traits

Components use the existing examine signal.

**`handle_pulse`, `handle_shock` and `handle_pain` are deleted.** The physiology replaces
them (health review §5.4).

**Reagent `on_mob_life` (124) becomes the Metabolism system:**
- uptake scaled by `BF_METABOLISM`
- per-reagent effects
- overdose accumulation
- one reconcile per cycle through a dirty bit

**Limb `take_damage` (179) becomes body-internal:** `spill_to_internal_organ`,
`apply_wounds`, `try_dismember`, `spread_overflow`.

**`droplimb` (136) becomes** message, remains and detach.

### 4.7 Status effects

The stun, weaken, paralysis and sleep counters (about 570 references) move onto
`/datum/status_effect`, the TG framework already in the codebase:
- They exist only while active, expire by timer, and nothing polls them.
- The setters keep their names (`Stun(x)`); readers use `IsStun()`, `IsParalyzed()` and
  so on.
- The conversion is mechanical and done in one pass.

Minor effects (jitter, dizziness, blurred vision, stuttering) follow the same pattern.

### 4.8 As built (phase 2)

Phase 2 is a mechanical move: every old `Life()` step runs as a system, in the old order,
with no behaviour change. The code is in `code/modules/mob/living/life/` and the defines in
`code/__defines/life_systems.dm`.

- **Scheduler.** `/mob/living/Life(seconds, profile)` is the only `Life()` for living mobs. It
  builds a `/datum/life_context`, then runs the composition's systems in (phase, order). A system
  is skipped when its wake bit is clear, when its `period` doesn't divide the cycle, or when a
  gate blocked its `segment`. `tick()` may return `LIFE_SLEEP` (clear its wake bit) or
  `LIFE_HALT` (end the cycle).
- **Families and variants.** A family is one concern (for example `/datum/life_system/breathing`).
  Its variants mirror the mob path (`breathing/carbon/human` with `mob_type =
  /mob/living/carbon/human`). A mob gets the variant with the most derived `mob_type`, and a
  variant's `..()` reaches its parent mob type's variant, exactly like the old `handle_*`
  override chains. Helpers that used to be separate procs (`breathe()`, `handle_breath()`,
  `handle_hud_icons_health()`) are procs on the family.
- **Life sets.** `/mob/living/var/life_set` picks the sequence: living, robot, AI, pAI, decoy,
  or delist (preview dummies and announcers). The silicon `Life()` procs never called the living
  parent, so they compose from their own families.
- **Gates and segments.** An old `if(...) return`, or an `if` around a block of hooks, became a
  gate system that blocks a segment for the rest of the cycle (`LIFE_SEG_LIVING`,
  `LIFE_SEG_LIVING_ALIVE`, `LIFE_SEG_LIVING_STATUS`, the human vitals segments,
  `LIFE_SEG_SIMPLE`). An early return before `..()` in a subtype became `LIFE_HALT` from its
  `type_pre` variant.
- **Subtype code.** Code a subtype ran before `..()` is a `type_pre` variant. Code it ran after
  `..()` is a `type_post` variant, whose `. = ..()` yields the legacy return value (for simple
  mobs, TRUE alive and FALSE dead). Simple mob `handle_special()` overrides are `special` variants.
- **Phases.** The move kept the legacy sequence, so each system sits in the phase where its code
  ran: `LIFE_PHASE_TAIL` holds the code subtypes ran after the living core (the human, alien,
  simple mob and bot tails and the `type_post` variants). Phases 3-5 re-home those systems.
- **Composition cache.** `GLOB.life_system_compositions`, keyed by mob type plus the extra
  (component-provided) systems. `recompose_life()` rebuilds it and calls `attach()` and
  `detach()`.
- **Trait systems.** The 16 `COMSIG_LIVING_LIFE` listeners are `/datum/life_system/trait/*`.
  A component calls `add_trait_life_system()` when it attaches and `remove_trait_life_system()`
  when it detaches. The signal is gone.
- **Species hooks.** `handle_environment_special()` and `handle_npc()` are species strategy calls
  (`environment_effects()`, `npc_behaviour()`). `handle_species_components()` became the
  species components system.
- **Public entry points.** Code outside `Life()` uses `refresh_hud()`, `refresh_vision()`,
  `refresh_glow()`, `process_chemicals()`, `process_organs(force)` (humans) and
  `run_life_system(family)`.
- **Hibernation.** Phase 2 only added the plumbing, with hibernation off. Phase 5 turned it on
  for every mob; see §4.9.
- **Profiling.** When SSmobs samples a mob, the scheduler times each system and SSmobs logs
  `MOB_SYSTEM_PROFILE system=... estimated_cost_ms=... estimated_calls=...` next to
  `MOB_PROFILE`. SSmobs passes elapsed seconds; systems keep their per-cycle amounts until
  they are rewritten to scale by `ctx.seconds`.
- **Lint.** `tools/ci/check_grep.sh` rejects `Life()` overrides on living mobs and `handle_*`
  Life hooks on mobs, species and traits.

### 4.9 As built (phase 5): sleep rules, wakes and hibernation

Hibernation is on for every mob, players included (`MOB_HIBERNATION_ENABLED`, runtime switch
`GLOB.mob_hibernation_enabled`). A mob leaves the `SSmobs` run once all of its systems are
asleep, and comes back on the first wake.

**Sleep rules.** A system says when it has nothing to do:
- `idle(self)` returns TRUE when the system can sleep until its `bit` is woken. The default is
  FALSE (never sleeps), so a system nobody has audited keeps its mob awake. It must be cheap
  and read-only, because the hibernation audit calls it on mobs that aren't ticking.
- `rewake_delay(self)` is for an idle system that still drifts slowly. It returns the
  deciseconds after which the system wakes anyway (a per-mob timer, `life_wake_in()`).
- `woken_by` names the producers that wake it. The audit prints it when a wake was missed.
- A family root's rule covers only the root (`type == /datum/life_system/<family>`). A variant
  with its own tick code stays awake until it declares its own rule.

**The scheduler.** After each system ticks, `Life()` asks `idle()`. A bit goes to sleep when
every system on it that was considered this cycle is idle, and nothing woke that bit during
the cycle. Some systems don't run in a given cycle (period skip, blocked segment). They keep
their bit awake if they still have work, except in the segments a dead mob never runs
(`LIFE_SEGS_BLOCKED_WHEN_DEAD`). Gates (`LIFE_SYS_GATE`, including `simple_vitals`) run
whenever the mob runs and never keep it awake. Nothing sleeps in a cycle that halted, or that
a transforming or nullspace gate stopped (`ctx.no_sleep`). When no bit other than the gate
bit is left, `life_hibernate()` parks the mob.

**Wake and hibernate live in exactly one proc each.**
- `/mob/living/proc/life_wake(bits, reason, partial = FALSE)` sets bits. A hibernating mob
  wakes whole, so every system gets one pass to re-check its rule. Only the timer passes
  `partial`. The next `Life()` gets nominal seconds, not the length of the nap.
- `/mob/living/proc/life_hibernate(reason)` parks the mob.
- `SSmobs.hibernating_mobs` and `life_hibernating` are written only there;
  `tools/ci/check_grep.sh` rejects other writes. Any other waker, such as SSreactor's REACT_ON
  path, calls `life_wake()`.

**Producers** (wake groups in `code/__defines/life_systems.dm`):

| Event | Where | Wakes |
|---|---|---|
| injury, treatment, full heal | `injure()`, `mend()`, `fully_heal()` | `LIFE_WAKE_BODY` |
| any body change: afflictions added or removed, severity bands, factors, reagents (`on_reagent_change`) | `/datum/body/proc/invalidate()` | `LIFE_WAKE_BODY` |
| stun, weaken, paralysis, sleep, confusion, blindness setters; start pulling | `mob.dm` setters → `on_status_counter_changed()` | `LIFE_WAKE_STATUS` |
| moving (air, area, light, gravity, hazards, belly) | `/mob/living/Moved()` | `LIFE_WAKE_MOVED` |
| equipping or unequipping | `/obj/item/equipped()`, `/mob/proc/remove_from_mob()` → `on_equipment_changed()` | `LIFE_WAKE_EQUIPMENT` |
| stat change | `/mob/living/set_stat()` | all |
| client login or logout | `/mob/living/Login()`, `Logout()` → `on_client_changed()` | all |
| modifier added, instability, disease | `add_modifier()`, `adjust_instability()`, `addDisease()` | `LIFE_SYS_UPKEEP` |
| species, plan or trait change | `recompose_life()`, `add_life_system()` | the new systems' bits |

**Rules in place** (the rest default to awake):

| System | Sleeps when | Timer |
|---|---|---|
| upkeep | no ghost follows and no spell buttons | |
| light (root) | the applied glow matches the wanted glow | |
| breathing, blood, chemicals, random events, environment, special, addictions, type_pre (roots) | always (roots are no-ops) | |
| type_post (root, carbon, simple mob) | always (return value only) | |
| mutations, radiation (roots) | no component listens to the signal | |
| afk | always | 30 s with a client |
| ambience | always | until the next replay with a client |
| movement | not pulling or grabbing | 30 s with a client (gravity) |
| status (root) | conscious or dead, and `body.life_settled()` | |
| disabilities (root) | eyes and ears recovered, blind alert gone, no disability component | |
| statuses (root) | every counter at 0 and every alert cleared | |
| canmove (root) | not stunned, weakened, paralysed or asleep | |
| hud, vision (roots) | no component takes over the HUD or vision | 5 s with a client (darksight) |
| modifiers, instability, diseases, tf holder, vr derez | nothing to expire, decay, spread or link; a VR mob inside the VR area | |
| simple statuses, supernatural, healing, guts | counters at 0; purge 0; not hurt or not fed; no organ objects | |
| environment (simple mob) | the air is survivable and the body has nothing for it to treat | 15 s (air changing in place) |
| human hud refresh, voice, visible name | always | 1 min; 10 s; 10 s |

A healthy idle simple mob hibernates within two cycles. Humans still run their physiology,
HUD, vision and tail systems every cycle, and robots, the AI and pAIs their own sets. They
sleep individual bits but don't hibernate until those systems declare rules (the physiology
work, diagnosis, cyborg phases).

**Status effects.** The counters (`stunned`, `weakened`, `paralysis`, `sleeping`,
`confused`, `eye_blind`) stay as they are. Their setters wake `LIFE_WAKE_STATUS`, and the
statuses systems run only while a counter or alert is live. Moving them onto
`/datum/status_effect` (§4.7) is still to do.

**Missed-wake safety net.** The audit is a debugging aid, not a production feature:
- In unit test and `TESTING` builds it always runs, and a missed wake fails the run
  (`stack_trace()` plus `Fail()` on the current test).
- On servers it's off unless the `MOB_HIBERNATION_AUDIT` config flag is set, or an admin
  uses the Debug verb "Toggle Hibernation Audit" for the round (logged with the admin's key).

When enabled, every `MOB_HIBERNATION_AUDIT_INTERVAL` (30 s),
`SSmobs.audit_hibernation()` checks two groups:
- up to 400 hibernating mobs, round robin
- up to 100 awake mobs that have sleeping systems

For each mob it asks every sleeping system's `idle()`. If a rule no longer holds, a producer
changed the mob without calling `life_wake()`. The audit logs `MOB_HIBERNATE_AUDIT: MISSED
WAKE` to the runtime and world logs, naming the mob, the system and its `woken_by`, and wakes
the mob. Direct writes to `eye_blurry`, `druggy`, `silent`, `stuttering` and similar, and glow
toggles on hibernating mobs, are the known sources. Waking whole from hibernation also clears
up stale counters on any later wake.

**Logging.**
- `MOB_HIBERNATE_SUMMARY` is always on, one line every two minutes next to `MOB_PROFILE`.
  It gives the hibernating count, hibernations, wakes, audits, missed wakes and the top wake
  reasons.
- Per-transition `MOB_HIBERNATE:` lines (bits put to sleep, hibernate, wake with reason and
  nap length) are behind `MOB_HIBERNATION_TRACE`, runtime switch
  `GLOB.mob_hibernation_trace`.
- The `SSmobs` stat panel shows `H:` hibernating.

**Measuring.** The `idle_mobs` benchmark (`code/modules/benchmarks/scenarios.dm`) spawns idle
mice and humans on a fixture. It measures `SSmobs` with hibernation off, then on, and reports
how many mobs hibernated and the awake bits left by type.

---

## 5. Cyborgs, drones and the AI

### 5.1 What is wrong

- **Bugs:** 8, 9, 13, 14 and 15 above.
- **God procedures:**
  - `create_mob_hud` (234 lines)
  - `robotanalyzer/do_scan` (190)
  - `attackby` (179)
  - the dogborg sleeper's `clean_cycle` (157)
  - six `has_*_upgrade` procs (106)
  - `update_icon` (104)
  - `ClickOn` (101)
  - `handle_regular_status_updates` (92)
  - `emag_act` (84)
  - `attack_hand` (83)
- **`robot.dm` has 1,761 lines, 78 vars and about 95 procs.** It covers lifecycle,
  naming, tools, petting and vore, access, appearance, power, AI link, laws, emag,
  riding and upgrade detection.
- **Components are binary.** A part either works or doesn't, and a check allocates a
  list every call (four or more times per tick, on every step, and up to 22 times per
  UI refresh).
- **Dogborg code runs through the base robot:**
  - `sleeper_state`
  - riding set up for every borg
  - sleeper checks in upgrade detection
  - death eject
  - ore bag and pounce handling on equip
- **Module and subtype checks sit in shared code:** events, door assemblies, trash,
  emotes, and a drone special case in `attackby`.
- **Duplication:**
  - The emag law override is written twice.
  - Three `init()` overrides skip `..()`.
  - The component set is copy-pasted.
  - Module slot logic is written three times.
  - Hats are handled separately for robots and drones.
  - Diagnosis is rendered seven different ways.
- **Death is decided in three places:** the machine plan, drone `Life()` and the drone
  reboot check.
- **The robot–AI link is a raw reference on both sides.** It is written by hand in shell
  deploy and the malf hack, which never unlinks the previous AI. Law sync is pull-only.

### 5.2 Target

**Components become body parts.**
- `ROBOT_SLOT_*` defines replace the string keys. Each slot is a synthetic part and an
  affliction location.
- Function is graded, 1 − load/max, and exposed through static factor tables:
  - actuator → `BF_SLOWDOWN` and `BF_MOTOR_CONTROL`
  - camera → `BF_VISION`
  - radio → a comms factor
  - diagnosis unit → the detail level of self-diagnosis
- Destruction stays a threshold event.
- A removed part carries its affliction datums, so damage is never erased and recreated
  (bug 15).
- Synthetic afflictions sit on their slots:
  - `power_fault` on the power bus
  - `coolant_leak` and `thermal_runaway` on a new cooling slot
  - `actuator_misalignment` on the actuator
  - `processor_corruption` on the core
- Only the plan decides death: core destroyed, or load at least 2× endurance. Drones
  only choose their remains in `death()`.

**Power and heat are the machine physiology** (health review §5.10):
- pump = deliverable power × power-bus integrity
- circulation = cooling integrity
- demand = the cached draw of components, modules and lights, plus ambient heat

A shortfall builds heat debt (thermal runaway) or causes brownout (processor faults and
unconsciousness). Consciousness comes from the plan, and the stat code in robot `Life()`
is deleted (fixes bug 8).

**One power ledger.**
- `draw_power(joules, source)` and `add_power(joules, source)` are the only writers, and
  a lint rule bans direct `cell.charge` writes (bug 14).
- Demand is cached and recomputed on toggle, install, equip or lights change, instead of
  summed every tick.
- An EMP is `injure(INJURY_ELECTRIC, x, slot, affliction = power_fault)`. `emp_act` calls
  its parent once (bug 9), and the cell's robot special case goes away.

**Splits:**
- `attackby` → `install_component`, `insert_cell`, `swipe_id`, `apply_upgrade`,
  `install_bolt`, `cable_act`.
- `crowbar_act` → `open_cover`, `pry_component`, `extract_mmi`.
- A virtual `upgrade/proc/is_installed(R)` replaces the six `has_*_upgrade` procs.
- `update_icon` → overlay providers: base, status, equipment, belly, panel, hat. The
  sprite datum is resolved in `Initialize`.
- `ClickOn` → a shared `dispatch_modifier_click` plus a robot `can_click_act()`; the
  restraining-bolt check is written once.
- `init()` → `setup_laws`, `setup_camera`, `setup_brain`, so subtypes override one piece
  and still call `..()`.
- One `subvert_laws(user)` serves robot and drone emags.
- `set_master_ai(AI)` maintains both sides of the link. The AI's laws emit a change
  signal that slaved borgs subscribe to.

**Dogborgs.** A belly component owns sleeper state, riding, death eject and the ore bag.
Modules gain `on_equip`, `on_death`, `overlays` and `sprite_class` hooks. The base robot
has no dogborg checks.

**Diagnosis.** All seven renderers call `body.diagnose(profile)`. The profiles are glance,
robot analyzer, self (gated by the diagnosis unit), sleeper and admin.

**Robot life systems:**

| System | Activation |
|---|---|
| Power | continuous; cheap once demand is cached |
| Body | continuous while there are afflictions or physiology is unsettled |
| Status | status effects |
| Senses | event: component change |
| HUD | event: band change |
| Lights | event: toggle |
| Laws | event: law-change signal |
| Countdowns (killswitch, weapon lock) | timers |

**The AI.**
- A machine plan subtype for the AI makes the backup capacitor a pump source, giving one
  death rule.
- `Life()` splits into power, vision and APU.
- The power-loss `spawn` routine becomes a timer-driven state machine.
- The AI core and AI shells share a plan.

---

## 6. Proteans and prometheans

### 6.1 What is wrong

- **The two-mob holder pattern.**
  - Going into blob form parks the human in nullspace and hands control to a
    `simple_mob`. The body freezes (bug 10).
  - The blob forwards only part of the health API, so `fully_heal`, `is_injured`,
    `find_affliction` and `get_endurance` reach the blob's own empty body.
  - The blob has no reagent holders, so it can't be medicated.
  - Worn gear stays on the parked human and still armours the blob.
  - Nutrition, confusion, radiation and paralysis are copied every tick. OOC notes and
    languages are copied at each switch.
  - Prey sit inside a nullspace mob for 1.3 seconds during the switch.
  - The promethean blob shares the human's belly list object, and its death deletes the
    blob without returning the bellies.
- **Per-character state lives on the species datum** (`OurRig`, `pseudodead`, blob style).
  Copying the species drops it, and callers save and restore the rig by hand.
- **Healing bypasses `mend()`** (bug 11). One nanite body has three biologies: nanoform
  limbs, synthetic organs, and a whole-body biology from the `synthetic` var. The blob
  claims `isSynthetic()` but is organic.
- **Death and revival are special cases.**
  - Pseudo-death is a hand-written counter.
  - `make_alive` edits the global mob lists and `stat` directly.
- **Powers.**
  - Each of 15 verbs works out again which form it is acting as.
  - The blob has seven wrapper verbs.
  - Ability objects cast `usr` blindly and dispatch with `call()`.
  - There are six near-identical dragon branches and seven Dullahan branches.
  - `appearance_switch` is 353 lines, and the blob's `update_icon` (161 lines) repeats
    the same overlay block 13 times.
- **Copy-paste between protean and promethean:** the into-blob and out-of-blob code,
  `calculate_health` and the HUD (a third copy lives in `simple_mob`), and the
  forwarding overrides.
- **Promethean per-tick work** scans the turf to clean it, redraws blood, and makes up to
  12 injury-load calls. Its regeneration records load before and after each `mend()`,
  although `mend()` already returns the amount healed.

### 6.2 Target: one character, one mob, many forms

**Recommended: forms as components of the character's own mob.**
- The character mob stays in the world at all times.
- A `/datum/component/forms` holds the current `/datum/form`: human, protean blob or
  promethean blob. Dragon and Dullahan are blob styles, which are data.
- A form declares:
  - its appearance: icon, size, offsets, layers, and whether the human body is drawn
  - its movement profile: speed, pass flags, whether it can be picked up
  - its capabilities: hands, inventory, equipment, speech, rig
  - its injury multipliers (the slime's ×0.75 physical and ×2 thermal)
  - its factor contributions, available powers and HUD variant
- Switching form swaps the datum, redraws the appearance, locks or unlocks the
  inventory, and sends `COMSIG_FORM_CHANGED`.
- Health, reagents, mind, bellies, languages and OOC notes never move, because nothing
  changes mobs.
- This deletes every forwarding override, the copying, the frozen-body bug, the belly
  transfer and the dangling-reference class of bugs.
- The protean rig holds the character mob the way a mob holder does. The mob has a real
  `loc` inside the rig and keeps living.

**A short spike first.** Before committing, prove on a human mob with the form component
the capabilities the blob gets from being a `simple_mob`:
- movement and attack profile
- being picked up
- the big-sprite offsets
- vore interactions
- rig integration

If one of them truly needs `simple_mob`, the fallback is **one body shared across two
mobs**: the blob points at the character's body, and a `body.host` field names the mob
currently being played. That fixes the health bugs, but inventory and reagents stay
split, so it is second best.

**Nanoform body plan.** `/datum/body/humanoid/nanoform` has nanoform biology for every
part and for the whole body.
- **Breathing:** factor baselines pin the breathing factors.
- **Pump:** comes from orchestrator power.
- **Refactory:** contributes metabolism, healing, slowdown and accuracy factors.
- **Regeneration:** a `TREAT_REGENERATION` treatment source from refactory stock ×
  `BF_HEALING`. Steel is charged from `mend()`'s return value, so no modifier is needed.
- **Pseudo-death:** becomes a `core_dormancy` affliction, held alive through
  `COMSIG_LIVING_BODY_STATUS`.
- **Revival:** the calibration, plating-repair and defibrillation tags revive it. No
  `make_alive` or list editing.

**State.** Per-character state (rig, dormancy, blob style) moves from the species datum
to the form component. Species datums become stateless.

**Powers.** A `/datum/protean_power` registry: cost, allowed forms, `can_use()`,
`activate()`. The acting form is resolved once, in the base. Verbs, hotkeys and the stat
panel are generated from the registry.

**Appearance.** Blob styles become data (icon, size, offsets, layers). `update_icon` loops
over layers, and import/export serialises the data, which fixes the Dullahan field bug by
construction.

**Prometheans:**
- Regeneration contributes to `BF_HEALING`, gated by stillness, warmth and pressure.
  Stillness is a timer reset on `Moved`.
- Water becomes a dissolution affliction.
- Cleaning runs on turf entry and on equip.
- Form code is shared with proteans through the form component.

**File splits:** `protean_powers.dm` splits into form, refactory, rig, host and appearance
files.

---

## 7. Other mob types

- **Simple mobs.** Environment tolerance becomes event-driven through gas dependencies.
  Regeneration is continuous only while injured. AI already sleeps through `SSai`. The
  split `death()` is merged.
- **pAI.** Uses the body plan; the cable check becomes an event.
- **Brains, aliens and constructs.** They get system sets like everything else. Their
  `handle_hud_icons_health` overrides become HUD elements.

---

## 8. Unified roadmap

This replaces section 7 of `doc/health_system_review.md`. Every phase:
- compiles clean and keeps the suite green
- deletes what it replaces
- adds its lint rules and a changelog
- keeps and extends debug logging

| Phase | Work |
|---|---|
| 0: bugs | Health review bugs 1–7 and this document's 8–19. The serious ones first: 8, 9, 10, 11. |
| 1: body core | Health review phase 1: shared treatment loop, snapshot cache, location index, one harm and one heal path, organ targeting. |
| 2: life scheduler | The system framework, context, composition cache and per-system profiler. Every existing `handle_*` moves into a system with **no behaviour change** (a mechanical move). System sets for human, robot, AI, pAI and simple mobs; the `COMSIG_LIVING_LIFE` listeners become systems. Hibernation stays off. |
| 3: body factors | Health review phase 2. |
| 4: physiology | Health review phase 3, built as the Body, Breathing and Thermal systems, with asphyxia by mechanism (health review decision 3). |
| 5: event-driven activation | Sleep conditions for every system; gas dependencies; status effects replace the counters; event-driven HUD, senses and identity; the active organ set. Then mob hibernation: NPC and SSD mobs first. |
| 6: diagnosis | Health review phase 4. |
| 7: cyborgs, drones, AI | Parts and factors, machine physiology, the power ledger, the splits, the dogborg component. |
| 8: proteans and prometheans | Form-component spike, then forms; the nanoform plan; the powers registry; appearance as data. |
| 9: surgery | Health review phase 5. |
| 10: stabilisation content | Health review phase 6. |
| 11: cleanup | Remaining splits, the `isSynthetic` sweep, naming, magic numbers. |

The scheduler (phase 2) comes before factors and physiology so that phases 3–5 are
written once, inside systems, instead of into today's god procedures and then moved.

---

## 9. Testing and enforcement

**Tests:**
- Per-system wake and sleep tests: change the input and assert the mob is awake; hold it
  steady and assert the system sleeps.
- A debug hibernation audit that samples sleeping mobs, as `audit_reactive_sleepers`
  does for machines.
- Cost tracking: the per-system profiler logs cost, and phase 5 sets a budget for a
  healthy idle human.
- The form tests (phase 8): switching form keeps afflictions, reagents, bellies and
  statuses ticking; a switch leaves no references on a deleted mob.

**Lint rules:**
- no `Life()` overrides outside the scheduler, and no new `handle_*` hooks (phase 2)
- no `SSair.times_fired` in mob code (phase 0)
- no direct `cell.charge` writes outside the power ledger (phase 7)
- no per-character state on species datums (phase 8)

---

## 10. Decisions needed

1. **Hibernation scope.** Decided: all mobs, players included (doc/refactor_brief.md). Built in
   §4.9; a player's mob hibernates as soon as its composition has nothing awake.
2. **Proteans and prometheans.** One mob with forms, after the spike, rather than one body
   shared across two mobs? *Recommendation: forms.*
3. **Scheduler before factors** (phase 2 ahead of phases 3–4), so the physiology is built
   once, inside systems? *Recommendation: yes.*
4. **Start phase 0 now**, all 19 bugs? *Recommendation: yes.*
