# Balance baseline

Reference numbers from the medical and combat balance harness
(`code/modules/balance/`), run on 2026-09-23 against master `9c9626a0c3` on the
unit-test map (`virgo_minitest`), BYOND 516.1687. The harness changes nothing; it
measures. Run it before and after a balance change:

```
tools/build/build.sh balance                       # every scenario; stored in data/balance/runs/
tools/build/build.sh balance --arg=scenarios=ttk   # a subset
tools/build/build.sh balance-compare               # previous run against the latest
tools/build/build.sh balance-compare --base=<run> --head=<run> --threshold=5
bash tools/dq_focused_test.sh /datum/unit_test/dq_balance_harness   # the same run as a test
```

Every run writes `data/balance/results.json`: one flat key per number
(`ttk.pistol_9mm.security_vest.hits_to_kill`), a unit per key, and for each
scenario its status, runtimes, duration, notes and any promised key that went
missing. `null` (shown as "never" below) means the event didn't happen within the
scenario's cap. `balance-compare` lists every key whose value moved by more than
the threshold (default 0%) or changed between a number and "never".

## How it measures

- Each trial spawns fresh mobs on a breathable floor, reseeds the RNG
  (`rand_seed(1337)`) and drives `Life()` directly, 2 s per cycle. Harm goes
  through `injure_by()` / `injure()` with the real armour soak. Treatment goes
  through reagents in the blood and the tools' own procs (`apply_to_limb()`,
  `apply_tourniquet()`, `apply_ventilation()`, `perform_cpr()`,
  `clear_airway()`, `defibrillate_heart()`). Plain gauze is modelled as what a
  gauze roll does: `TREAT_WOUND_PACKING` 1 on each open wound of the limb.
- `world.time` doesn't advance during a trial, so anything timed by `world.time`
  (a bag-valve mask's 12 s drive support, CPR's compression window, modifier
  durations) holds for the whole trial. The harness re-applies BVM every 12 s and
  CPR every 7 s anyway, so read those rows as "done continuously and correctly".
- Weapon cadence: melee uses the weapon's `attackspeed`, thrown objects one click
  (0.8 s), projectiles the base gun `fire_delay` (0.6 s). Melee and thrown damage
  is `force` / `throwforce` with no user modifiers. Projectile damage is the
  projectile's `damage`; agony, stuns and on-hit effects aren't modelled, which is
  why the taser and the stun beam never kill.
- Runs are close to deterministic but not exactly: the two runs of this code
  differed on a handful of bleed-out values (for example
  `bleedout.cut_massive.tourniquet`: 602 s, then 506 s). Treat differences of a
  few percent in the bleed-out table as noise.

## Caveats found by the control scenario

The `baseline` scenario is a control: the site's air (101.3 kPa, 21% O2) and an
unhurt human left alone for 60 s. That human keeps full ventilation, 100% SpO2 and
no oxygen debt, **but its stat is UNCONSCIOUS from the first Life cycle**: its
`sleeping` counter is 2 and its consciousness is 100, with no afflictions. A
client-less test human falls asleep. Consequences:

- Every "time to unconscious" and "time to crit" for a human is 2 s and means
  nothing. They stay in `results.json`; the tables here show them only where they
  carry information (cyborgs).
- Sleep speeds regeneration (`REGENERATION_SLEEP_MULT`), and the human life tick
  gives a sleeper `TREAT_ANALGESIC` 3 per cycle, so natural healing and pain decay
  in these numbers are a sleeping patient's, not an awake one's.
- A follow-up should read consciousness from `body.get_consciousness()` /
  `is_critical()` instead of `stat`, or keep the test mob awake, and re-run.

## Baseline

| Measure | Value |
|---|---|
| Site pressure | 101.34 kPa |
| Site O2 share | 0.21 |
| Healthy human after 60 s: ventilation, SpO2, breath quality, oxygen debt | 1, 100, 1, 0 |
| Healthy human: consciousness / `sleeping` after one Life | 100 / 2 (stat UNCONSCIOUS) |

## Time to kill

Hits to kill, with seconds in brackets. Hits land at the torso (cyborgs: spread over components) at the listed cadence; "never" = still alive after 200 hits or 180 s.

### Hits to kill (seconds)

| Weapon | Raw | s/hit | unarmoured | security_vest | riot_suit | hardsuit | cyborg | protean |
|---|---|---|---|---|---|---|---|---|
| combat_knife | 20 | 0.8 | 16 (12 s) | 26 (20 s) | 75 (59.2 s) | 30 (23.2 s) | 20 (15.2 s) | 36 (28 s) |
| classic_baton | 10 | 0.8 | 31 (24 s) | 50 (39.2 s) | 150 (119.2 s) | 60 (47.2 s) | 40 (31.2 s) | 91 (72 s) |
| toolbox | 10 | 0.8 | 31 (24 s) | 50 (39.2 s) | 150 (119.2 s) | 60 (47.2 s) | 40 (31.2 s) | 91 (72 s) |
| spear | 5 | 1.4 | 60 (82.6 s) | 86 (119 s) | 66 (91 s) | 79 (109.2 s) | 80 (110.6 s) | never |
| stun_baton | 15 | 0.8 | 21 (16 s) | 33 (25.6 s) | 100 (79.2 s) | 40 (31.2 s) | 27 (20.8 s) | 66 (52 s) |
| energy_sword | 3 | 0.8 | 100 (79.2 s) | 168 (133.6 s) | never | never | 134 (106.4 s) | never |
| pistol_9mm | 20 | 0.6 | 15 (8.4 s) | 22 (12.6 s) | 17 (9.6 s) | 20 (11.4 s) | 20 (11.4 s) | 54 (32 s) |
| pistol_45 | 25 | 0.6 | 12 (6.6 s) | 17 (9.6 s) | 13 (7.2 s) | 16 (9 s) | 16 (9 s) | 37 (22 s) |
| rifle_545 | 25 | 0.6 | 12 (6.6 s) | 17 (9.6 s) | 13 (7.2 s) | 16 (9 s) | 16 (9 s) | 37 (22 s) |
| rifle_762 | 35 | 0.6 | 10 (5.4 s) | 12 (6.6 s) | 9 (4.8 s) | 12 (6.6 s) | 12 (6.6 s) | 20 (12 s) |
| shotgun_slug | 50 | 0.6 | 6 (3 s) | 9 (4.8 s) | 6 (3 s) | 8 (4.2 s) | 8 (4.2 s) | 14 (8 s) |
| laser | 40 | 0.6 | 5 (2.4 s) | 8 (4.2 s) | 6 (3 s) | 7 (3.6 s) | 10 (5.4 s) | never |
| laser_mid | 40 | 0.6 | 5 (2.4 s) | 7 (3.6 s) | 5 (2.4 s) | 6 (3 s) | 10 (5.4 s) | never |
| laser_heavy | 60 | 0.6 | 4 (1.8 s) | 4 (1.8 s) | 4 (1.8 s) | 4 (1.8 s) | 7 (3.6 s) | never |
| xray | 25 | 0.6 | 8 (4.2 s) | 8 (4.2 s) | 8 (4.2 s) | 8 (4.2 s) | 16 (9 s) | never |
| taser_electrode | 0 | 0.6 | never | never | never | never | never | never |
| stun_beam | 40 | 0.6 | never | never | never | never | never | never |
| plasma_stun | 5 | 0.6 | 40 (23.4 s) | 50 (29.4 s) | 40 (23.4 s) | 47 (27.6 s) | 80 (47.4 s) | never |
| phase_wave | 5 | 0.6 | 40 (23.4 s) | 58 (34.2 s) | 45 (26.4 s) | 53 (31.2 s) | 80 (47.4 s) | never |
| thrown_toolbox | 10 | 0.8 | 31 (24 s) | 50 (39.2 s) | 150 (119.2 s) | 60 (47.2 s) | 40 (31.2 s) | 91 (72 s) |
| thrown_spear | 7 | 0.8 | 44 (34.4 s) | 61 (48 s) | 48 (37.6 s) | 57 (44.8 s) | 58 (45.6 s) | 148 (118 s) |
| thrown_star | 15 | 0.8 | 20 (15.2 s) | 33 (25.6 s) | 100 (79.2 s) | 40 (31.2 s) | 27 (20.8 s) | 53 (42 s) |
| thrown_shard | 7 | 0.8 | 44 (34.4 s) | 72 (56.8 s) | never | 87 (68.8 s) | 58 (45.6 s) | 148 (118 s) |

### Time to crit

For humans (unarmoured, vest, riot suit, hardsuit, protean) every weapon "crits" at the first Life cycle (2 s). That is the sleep artifact described under Caveats, not a crit, so those columns are left out here (they are in results.json). Cyborgs don't sleep, so their numbers are real. Hits (seconds): combat_knife 18 (14 s); classic_baton 26 (20 s); toolbox 26 (20 s); spear 65 (90 s); stun_baton 20 (16 s); energy_sword 118 (94 s); pistol_9mm 17 (10 s); pistol_45 14 (8 s); rifle_545 14 (8 s); rifle_762 7 (4 s); shotgun_slug 4 (2 s); laser 7 (4 s); laser_mid 7 (4 s); laser_heavy 4 (2 s); xray 14 (8 s); taser_electrode never; stun_beam never; plasma_stun 64 (38 s); phase_wave 64 (38 s); thrown_toolbox 26 (20 s); thrown_spear 46 (36 s); thrown_star 18 (14 s); thrown_shard 46 (36 s).

### Damage applied by the first hit

What `injure_by()` returned for the first hit: after armour, resistance factors and the species and part multiplier.

| Weapon | Raw | unarmoured | security_vest | riot_suit | hardsuit | cyborg | protean |
|---|---|---|---|---|---|---|---|
| combat_knife | 20 | 10 | 12 | 4 | 10 | 20 | 16 |
| classic_baton | 10 | 5 | 6 | 2 | 5 | 10 | 8 |
| toolbox | 10 | 5 | 6 | 2 | 5 | 10 | 8 |
| spear | 5 | 2.5 | 3.5 | 4.5 | 3.8 | 5 | 4 |
| stun_baton | 15 | 7.5 | 9 | 3 | 7.5 | 15 | 12 |
| energy_sword | 3 | 3 | 1.8 | 0.6 | 1.5 | 3 | 2.4 |
| pistol_9mm | 20 | 10 | 14 | 18 | 15 | 20 | 16 |
| pistol_45 | 25 | 12.5 | 17.5 | 22.5 | 18.8 | 25 | 20 |
| rifle_545 | 25 | 12.5 | 17.5 | 22.5 | 18.8 | 25 | 20 |
| rifle_762 | 35 | 17.5 | 24.5 | 31.5 | 26.3 | 35 | 28 |
| shotgun_slug | 50 | 25 | 35 | 45 | 37.5 | 50 | 40 |
| laser | 40 | 40 | 28 | 36 | 30 | 40 | 60 |
| laser_mid | 40 | 40 | 32 | 40 | 34 | 40 | 60 |
| laser_heavy | 60 | 60 | 60 | 60 | 60 | 60 | 90 |
| xray | 25 | 25 | 25 | 25 | 25 | 25 | 37.5 |
| taser_electrode | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| stun_beam | 40 | 40 | 36 | 36 | 34 | 0 | 0 |
| plasma_stun | 5 | 5 | 4 | 5 | 4.3 | 5 | 7.5 |
| phase_wave | 5 | 5 | 3.5 | 4.5 | 3.8 | 5 | 7.5 |
| thrown_toolbox | 10 | 5 | 6 | 2 | 5 | 10 | 8 |
| thrown_spear | 7 | 3.5 | 4.9 | 6.3 | 5.3 | 7 | 5.6 |
| thrown_star | 15 | 15 | 9 | 3 | 7.5 | 15 | 12 |
| thrown_shard | 7 | 7 | 4.2 | 1.4 | 3.5 | 7 | 5.6 |

## Bleed-out

Time to death in seconds (time to unconscious in brackets); "never" = alive at 1200 s. Last column: blood left at the end, untreated.

| Wound | untreated | gauze | hemostatic_gauze | tourniquet | Blood left (untreated) |
|---|---|---|---|---|---|
| cut_small | never (2) | never (2) | never (2) | never (2) | 0.62 |
| cut_deep | never (2) | never (2) | never (2) | never (2) | 0.59 |
| cut_flesh | 922 (2) | never (2) | never (2) | never (2) | 0.41 |
| cut_gaping | 658 (2) | never (2) | never (2) | never (2) | 0.28 |
| cut_massive | 506 (2) | never (2) | never (2) | 506 (2) | 0.18 |
| puncture_flesh | 412 (2) | 398 (2) | 390 (2) | 378 (2) | 0.91 |
| puncture_gaping | 370 (2) | 362 (2) | 356 (2) | 350 (2) | 0.73 |
| puncture_massive | 312 (2) | 322 (2) | 318 (2) | 308 (2) | 0.52 |
| bruise_huge | 322 (2) | 326 (2) | 322 (2) | 308 (2) | 1 |
| arterial | 316 (2) | 314 (2) | 310 (2) | 308 (2) | 0.76 |

## Hypoxia

Seconds from onset; "never" = not within 900 s.

| Cause | Intervention | Unconscious | Brain lesion | Brain death | Death | O2 debt at end | Brain damage at end |
|---|---|---|---|---|---|---|---|
| airway_obstruction | none | 2 | 34 | 206 | 206 | 150 | 120 |
| airway_obstruction | bvm | 2 | 34 | 206 | 206 | 150 | 120 |
| airway_obstruction | cpr | 2 | 58 | 238 | 238 | 150 | 120 |
| respiratory_arrest | none | 2 | 34 | 206 | 206 | 150 | 120 |
| respiratory_arrest | bvm | 2 | 78 | 268 | 268 | 150 | 120 |
| respiratory_arrest | cpr | 2 | 56 | 238 | 238 | 150 | 120 |
| cardiac_arrest_vf | none | 2 | 34 | 206 | 206 | 150 | 120 |
| cardiac_arrest_vf | bvm | 2 | 34 | 206 | 206 | 150 | 120 |
| cardiac_arrest_vf | cpr | 2 | 34 | 208 | 208 | 150 | 120 |

## Treatment efficacy

A dose in the blood at t=0. "Treated" = down to 10% of the starting amount; "never" = not within 600 s.

| Condition | Treatment | Start | Left at 120 s | Time to treated (s) |
|---|---|---|---|---|
| trauma_40 | none | 20 | 100% | never |
| trauma_40 | bicaridine | 20 | 0% | 62 |
| trauma_40 | tricordrazine | 20 | 33% | never |
| burn_40 | none | 40 | 98% | never |
| burn_40 | kelotane | 40 | 60% | never |
| burn_40 | dermaline | 40 | 33% | never |
| toxin_30 | none | 30 | 99% | never |
| toxin_30 | dylovene | 30 | 0% | 38 |
| oxygen_debt_40 | none | 38 | 332% | never |
| oxygen_debt_40 | dexalin | 38 | 30% | never |
| brain_30 | none | 29.98 | 150% | never |
| brain_30 | alkysine | 29.98 | 47% | never |
| heart_20 | none | 19.98 | 146% | never |
| heart_20 | peridaxon | 19.98 | 115% | never |
| pain_60 | none | 78.5 | 0% | 14 |
| pain_60 | tramadol | 78.5 | 0% | 2 |

| Tool | Resolves in one application |
|---|---|
| hemostatic_gauze_stops_bleed | yes |
| airway_kit_clears_obstruction | yes |
| defibrillator_converts_vf | yes |
| tourniquet_stops_arterial_bleed | yes |

## Digestion (60 s)

| Mode | prey_injury_delta | prey_nutrition_delta | pred_nutrition_delta | prey_size_delta | prey_absorbed | prey_dead |
|---|---|---|---|---|---|---|
| hold | 0 | -1.5 | -1.5 | 0 | 0 | 0 |
| digest | 12 | -1.5 | 52.5 | 0 | 0 | 0 |
| absorb | 0 | -121.56 | 118.56 | 0 | 0 | 0 |
| drain | 0 | -121.56 | 118.56 | 0 | 0 | 0 |
| shrink | 0 | -1.5 | -1.5 | 0 | 0 | 0 |
| grow | 0 | -1.5 | -1.5 | 0 | 0 | 0 |
| size_steal | 0 | -1.5 | -1.5 | 0 | 0 | 0 |
| heal | -26 | 8.5 | -21.5 | 0 | 0 | 0 |

## Stasis

| Stasis | Unconscious (s) | Death (s) | Survival multiplier |
|---|---|---|---|
| none | 2 | 254 | 1 |
| light | 2 | 500 | 1.97 |
| moderate | 2 | 1262 | 4.97 |
| deep | 2 | 2500 | 9.84 |

## Suspicious numbers

Flagged for a human to look at. None of them were changed.

1. **Test humans fall asleep on their own** (see Caveats). This spoils every
   human crit/unconscious time and speeds up healing and pain decay.
2. **Armour raises the damage a hit applies.** An unarmoured torso takes half of
   every physical hit (knife 20 -> 10, 9mm 20 -> 10). A security vest lets 14 of a
   9mm's 20 through and a riot suit 18, and a riot suit lets a spear through for
   4.5 against 2.5 unarmoured. Armour turns the cut or pierce into blunt trauma,
   and blunt escapes the 0.5 multiplier that cuts and pierces get. Armour still
   lengthens time to kill (9mm: 15 hits unarmoured, 22 with a vest), so the
   numbers are consistent, but "damage applied" can't be read as protection.
3. **Proteans aren't killed by lasers, X-rays, energy weapons or a spear within
   3 minutes**, although they take 1.5x burn (a laser applies 60 of its 40).
   Every other target dies to a laser in 5-10 shots.
4. **The heavy laser ignores all armour** (60 of 60 applied through the vest, the
   riot suit and the hardsuit) and kills every human in 4 shots / 1.8 s. The X-ray
   also passes every suit untouched (25 of 25).
5. **The riot suit is weak against bullets**: it lets more of a bullet through
   than the vest or the hardsuit (9mm: 17 hits to kill, against 15 unarmoured and
   22 with a vest).
6. **Deaths in the bleed-out table that aren't blood loss.** Punctures, a huge
   bruise and an arterial bleed all kill in about 5-7 minutes whatever the
   treatment, with 50-100% of the blood left. `bruise_huge` kills at 322 s with
   the blood volume untouched. Hemostatic gauze and a tourniquet don't change
   those times, so something other than bleeding kills these patients.
7. **Small and deep cuts never kill** but still drain the patient to about 60% of
   their blood in 20 minutes. A tourniquet on a massive cut didn't extend
   survival in the second run (506 s, the same as untreated), although plain
   gauze saved the patient.
8. **CPR does almost nothing for VF** (death at 208 s against 206 s untreated),
   although the design says compressions cut the debt's growth to about a third.
   CPR helps an obstructed airway more than VF (238 s). A bag-valve mask does
   nothing for an obstructed airway or VF, which matches the design (it supports
   the breathing drive only).
9. **Every untreated hypoxia case dies at exactly 206 s**, with the first brain
   lesion at 34 s, whatever the cause. The cause only decides whether delivery is
   zero, not how fast it fails.
10. **Oxygen debt grows in a breathing patient.** 40 debt added to a healthy human
    had grown to 332% of that after 120 s untreated. Dexalin brings it down to 30%
    but never to 10% within 10 minutes.
11. **Untreated brain and heart lesions grow** (brain 30 -> 150% at 120 s, heart
    20 -> 146%). Peridaxon doesn't stop the heart lesion growing (115%).
12. **Burn chems are slow.** Neither kelotane nor dermaline brings 40 burn down to
    10% within 10 minutes, while bicaridine clears the same trauma in 62 s and
    dylovene clears toxin in 38 s.
13. **Pain vanishes in 14 s untreated** (78.5 -> 0). That is the sleep analgesia
    from item 1 as much as natural decay.
14. **The energy sword measured at force 3.** It spawns switched off, so its row
    is the inactive blade, not a real weapon number.
15. **Absorb behaves like drain over 60 s** (identical nutrition transfer, prey not
    absorbed), and shrink, grow and size steal change the prey's size by exactly
    0 in 60 s.
16. **Digest does 12 injury in 60 s** to an unarmoured human prey, so digestion
    takes many minutes to kill.

Numbers that look right: stasis multiplies survival by 1.97 / 4.97 / 9.84 for
light / moderate / deep stasis, against the expected 2 / 5 / 10, and all four
single-use tools resolve their condition in one application.
