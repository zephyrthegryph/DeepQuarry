# Base-type vars: one home for every var (approved 2026-10-10)

Every var declared on a base type (`/atom`, `/atom/movable`, `/obj`, `/obj/item`, `/obj/machinery`, `/mob`,
`/mob/living`, `/mob/living/carbon`, `/mob/living/carbon/human`) gets exactly one home. Anything else on a base
type fails the `base_vars` lint (shrink-only baseline, `tools/ci/base_vars_baseline.txt`). Forms:
`final_api.html` section 6 ("Trait blocks" and "Homes for base-type vars").

| Kind | Home | Form |
|---|---|---|
| Per-type constant overridden by subtypes (item force/reach/slot_flags, mob bump/swap/push flags, can_climb, makes_dirt, mob_class, see_invisible_default) | trait block | `item_combat(...)` on the base, `configure(item_combat(force = 10))` on a subtype, `set_trait(src, trait, field = v)` at run time (copy-on-write, publishes the trait key), read `combat_of(I).force` |
| Character identity and preferences (hair/eye/skin colours, markings, synth colours, digitigrade, lip, age, origin, faction, religion, records text, flavour text, nickname, loadout choices, custom say verbs, the vore toggles and messages) | profile record | `profile(nameof(appearance), /datum/record/appearance)`; a record holds data fields only (`TRACKED_DATA` for drawn fields); records: appearance, identity (human), vore_prefs (mob) |
| Client HUD state (screen refs, plane_holder, vis_enabled, planes_visible, zone_sel, spell/ability masters) | HUD datum | `/datum/hud` with `hud_element(nameof(x), /screen/type, when = PROC_REF(...))`; the mob `owns_one` hud, built on login, dropped on logout; read `hud_of(M)?.x` |
| Live simulation state | the owning domain, else `TRACKED` in place with a setter | nutrition/hunger_rate: body metabolism; on_fire/fire_stacks/decay: burning behaviour; fear/tiredness/flying: status contributions; stat/incapacitated: `TRACKED` |
| Rare per-instance state (special_voice, xylophone, custom_heat/cold, dsoverlay, selected_image, exploit_addons, ...) | sparse slot | `sparse(type, nameof(x), type = ...)`, `sparse_get(A, x)`, `sparse_set(A, x, v)`; one lazy assoc list per instance; `code/datums/sparse_vars/*` and their GLOB type tables migrate (type defaults become trait blocks) |
| References (master, hidden_uplink, vore_selected, spont_belly_*, tf_form/tf_form_mind, nest) | relations | `owns_one` / `links()` / `slot()` (existing) |
| Cooldowns (next_move, resist_cooldown, lastpuke, fear_sound_cooldown, last_special) | cooldown table | `cooldowns(a, b, ...)`, `cooldown_ready(M, a)`, `cooldown_start(M, a, dur)`; one lazy list; `COOLDOWN_DECLARE` on a base type is banned |
| Dead (no reads, or written and never read) | deleted | the analyzer report (`analyze base-vars-dead`) drives it |

## Light

`light_range`, `light_power` and `light_color` on `/atom` (about 700 overrides, 880 reads, 270 `set_light` calls): the
look is the only light source.

- A per-type default becomes `look_glow(GLOW(r, p, c))` (codemod over the overrides).
- A run-time change is tracked state the draw reads (`L.glow(...)`).
- An ad-hoc `set_light(r, p, c)` becomes `set_glow(src, GLOW(r, p, c))`, a sparse glow override applied by the base draw.
- The light system reads only `glow_of(A)`.
- Then the three vars and `/mob/living` `last_glow_*` are deleted.

## Tooling

- `base_vars` lint accepts trait blocks, profile records, HUD elements, `TRACKED`/`STAT`, sparse slots and cooldowns;
  anything else on a base type fails.
- `records_data_only` lint: a `/datum/record` subtype declares data fields and accessors only.
- Analyzer report of vars with no reads or write-only (`analyze base-vars-dead`).
- Map loader: an edit of an unknown var that names a trait field goes through `set_trait()` (restores the Southern
  Cross omni mixer `active_power_usage = 7500`, lost when `uses_power()` landed).
- Admin VV shows a holder's trait blocks, owned records, HUD and sparse slots; edits route through the setters.

## Risky parts

- r_/g_/b_ triples collapse to colour strings: the codemod rewrites reads, a one-time preference savefile migration is
  tested on real save files, and pins on the human draw prove no visual change.
- Preference apply, cloning, DNA copy and shapeshift (`tf_form`) become record copies.

## Rollout and lanes

1 dead sweep, 2 trait blocks (items, mobs) and the map loader, 3 HUD, 4 profiles (appearance, identity, vore),
5 live state, 6 sparse, cooldowns and relations, 7 light vars.

- Lane A (`bv-traits`): docs, tooling (dead-var report, lint homes, map loader, VV), dead sweep, trait blocks, light.
- Lane B (`bv-hud`): HUD datum, live state, sparse slots, cooldowns, relations.
- Lane C (`bv-profiles`): profile records.

Each landing lowers `tools/ci/base_vars_baseline.txt`.
