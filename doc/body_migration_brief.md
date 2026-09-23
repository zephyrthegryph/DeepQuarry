# Body migration — agent brief

You are migrating one slice of the DeepQuarry (BYOND/DM) codebase off the old
health/damage-pool model onto the body/affliction system. **Read
`doc/body_architecture.md` first** — it is the contract. Also read the core:
`code/__defines/body.dm`, `code/modules/body/*.dm`, `code/modules/body/plans/*.dm`,
`code/modules/body/parts/limb.dm`, `code/modules/body/afflictions/systemic.dm`.

## The end state
After the migration, `code/modules/body/legacy_damage_api.dm` (the transitional
shim) is deleted along with the vars `health`, `maxHealth`, `bruteloss`,
`fireloss`, `toxloss`, `oxyloss`, `cloneloss`, `brainloss`, `halloss`. So in your
files there must be **zero** uses of:

- `adjustBruteLoss/FireLoss/ToxLoss/OxyLoss/CloneLoss/HalLoss/BrainLoss`, `set*Loss`, `get*Loss`
  (incl. `getShockBruteLoss`, `getActualBruteLoss`, `adjustBruteLossByPart`, `HealDamage`)
- `apply_damage`, `apply_damages`, `take_overall_damage`, `heal_overall_damage`,
  `take_organ_damage`, `heal_organ_damage` (on mobs)
- `updatehealth()`, `getMaxHealth()`, `setMaxHealth()`, `get_crit_point()`
- the vars above (read or write), `RoundHealth()`
- limb `brute_dam` / `burn_dam` outside the limb/wound slice (use `E.get_trauma()` / `E.get_burn()`)

## The replacements (see architecture §9 for the full table)
- Harm: `L.injure(INJURY_*, amount, zone = null, source = src_atom, armor_pen = 0, affliction = null, flags = NONE)`
  (add `INJURE_ARMORED` for hits from outside the body).
  Choose the kind that describes WHAT HAPPENED (blunt vs cut vs pierce; burn vs
  frostbite vs corrosive vs electric; toxin; asphyxia; radiation; cellular;
  neural; pain; digestion). `L.injure_many(alist(INJURY_BLUNT = x, INJURY_BURN = y), ...)`
  for combined hits. Weapon items: `I.injury_kind` (or `L.injure_by(I, amount, zone)`,
  which also handles mixed `injury_kinds` hits such as searing blades).
- Healing: `L.mend(TREAT_*, amount, zone = null)` — pick the mechanism
  (TISSUE_REPAIR, BURN_CARE, ANTITOXIN, OXYGENATION, GENETIC_REPAIR,
  NEURAL_REPAIR, ANALGESIC, HEMOSTATIC, PLATING_REPAIR / WIRING_REPAIR for
  machines, …). Generic "heal everything" (admin, rejuvenate, full regen) =
  `L.fully_heal()`. Partial generic regeneration = several `mend()` calls.
  **Reagents never mend for their core effect**: they declare `treatment_tags`
  (see `code/modules/body/treatment.dm`) and the body applies them each tick.
- Questions: `L.vitality()` (0..1 wellness — replaces health/maxHealth
  fractions and "health <= X" thresholds: health% p ⇒ vitality() <= p), `L.is_critical()`
  (replaces `health < 0` / `< get_crit_point()` / crit checks), `L.get_endurance()`
  (replaces maxHealth/getMaxHealth as a toughness scale), `L.injury_load(INJURY_CATEGORY_*)`
  (replaces get*Loss totals), `L.is_injured()`, `L.find_affliction(type)`,
  `L.has_affliction(type)`, `L.current_pain()` (replaces getHalLoss/halloss reads).
  Absolute old-health comparisons between mobs → compare `vitality()` or
  `vitality() * get_endurance()`.
- Mob tuning: type defaults `maxHealth = N` were already converted to
  `endurance = N`. Runtime writes `maxHealth = x` → `endurance = x`;
  `health = maxHealth` (reset) → `fully_heal()` if it means "restore", else delete.
- Signals: old `COMSIG_TAKING_*_DAMAGE` / `COMSIG_CANCEL_*_DAMAGE` listeners →
  `COMSIG_LIVING_INJURE` (args: kind, list/amount_ref, zone, source, flags; return
  `COMPONENT_CANCEL_INJURY`); post-hit listeners → `COMSIG_LIVING_INJURED`.
- Modifier fields were already renamed (incoming_physical_percent, …,
  endurance_flat/percent, effective_*_resistance).

## Unique afflictions
Where a source genuinely deserves its own affliction (a specific venom, phoron
poisoning, a named disease effect, a magical curse, electrical burns…), create
it instead of a generic injury: pass `affliction = /datum/affliction/<name>` to
`injure()`. Author it like the existing ones in `code/modules/medical/conditions/*.dm`
(name, category, clinical_description, `injury_category`, `treated_by`,
`symptom_pool`, `pain_at_max`/`consciousness_at_max`, optional stages). Put new
afflictions in a NEW file under `code/modules/medical/conditions/` named for your
slice (e.g. `venoms.dm`). Be judicious — a handful of well-made ones beats dozens
of thin ones.

## Synthetic vs organic
Never branch on `isSynthetic()` just to pick damage/heal behaviour — the body
resolves biology per part. Afflictions declare `biology`; treatment tags declare
theirs. A welder repairing a robot limb is `mend(TREAT_PLATING_REPAIR, x, zone)`.
Mechanical simple mobs: set `biology = BIOLOGY_SYNTHETIC` on their type.

## Rules
- Edit ONLY files in your slice (listed in your prompt). If something outside
  your slice must change, don't touch it — list it in your report.
- Do **not** edit `deepquarry.dme`. List any new files in your report.
- Do **not** run the compiler (`dm.exe`) — other agents share the build output.
  Verify by reading carefully and grepping. The lead compiles centrally.
- Do not edit `code/modules/body/**` (the core) — propose core changes in your report.
- Follow CLAUDE.md DM standards (absolute paths, no `:` operator, SIGNAL_HANDLER, time defines).
- Preserve behaviour and balance as closely as the new model allows; where the
  old code did something the new model can't express, say so in the report.
- When done, grep your slice for every forbidden symbol above and report zero
  (or list the exceptions and why).

## Report format
1. Files changed (count + notable ones), new files (for the .dme).
2. Unique afflictions added.
3. Anything you could not migrate or that needs a core/other-slice change.
4. Behaviour changes a reviewer should know about.
