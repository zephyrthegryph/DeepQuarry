# Reagents and chemistry: the final forms

Status: sections 1, 2 and 4 are **built** (`rewrite/reagents`); section 3 is the plan for the reagent and effect tables; section 5 lists the
machines. The design it follows is `final_api.html` (section 11 "Reagents and food", 16.5, section 17's `DECLARE_REAGENTS` rows).

## 1. What changed

| Old form | Final form | Where |
|---|---|---|
| `DECLARE_REAGENTS(T, V, C)` on the root of a chain | `reagents(V, starts = C)` in `CAPABILITIES(T)` | `code/library/reagents/reagents.dm` |
| `DECLARE_REAGENTS(T, null, C)` on a subtype (most of the ~700 sites) | `configure(reagents(add = C))`: ADDS to the inherited contents | |
| `DECLARE_REAGENTS(T, V, C)` on a subtype | `configure(reagents(volume = V, add = C))` | |
| `DECLARE_REAGENTS_TINTED` / `_TYPED` | `tint = TRUE` / `holder = /datum/reagents/x` | |
| `DECLARE_REAGENT_FROM_VAR(T, V, "id", "amt")` | `reagents(nameof(V), starts_from = list(nameof(id) = nameof(amt)))` | |
| `DECLARE_NO_REAGENTS(T)` | `without(CAP_REAGENTS)` | |
| `DECLARE_NO_REAGENTS` then `DECLARE_REAGENTS` on one type | `configure(reagents(starts = C))`: REPLACES the inherited contents | |
| `reagents()` / `refine(CAP_REAGENTS, ...)` in a legacy `capabilities()` proc | the same entries in the block | the reagent tanks |
| a string volume (`"volume"`) | `nameof(volume)` (or a `PROC_REF` of a holder proc answering it) | |
| `calc_reaction_progress()` arithmetic | `vg_chem_reaction_progress()` (`verdigris/domains/chem/src/reaction.rs`) | section 4 |
| per-reagent uptake, dose and overdose arithmetic in `on_mob_life()` | one `vg_chem_metabolism_cycle()` per holder per Life cycle | section 4 |

The macros, the declaration table's reagent fields (`set_reagents`, `set_reagent_var`, `create_reagents_on`, ...), the legacy
`/datum/capability/reagents` and its `CAP_REAGENTS` path define, `refine()`'s `starts`/`add`/`volume` fields and the old converter
`tools/ci/decl_convert_reagents.py` are deleted. The names are a hard ban (`[lint.legacy_forms.lists] banned` in `tools/ci/lint_scopes.toml`).

## 2. The holder: `reagents()`

```dm
CAPABILITIES(/obj/item/reagent_containers)
	reagents(nameof(volume))                                              // every container: a holder of its (mapped) volume

CAPABILITIES(/obj/item/reagent_containers/food/snacks/donut)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 3, REAGENT_ID_SUGAR = 2)))

CAPABILITIES(/obj/item/extinguisher/mini)
	configure(reagents(starts = list(REAGENT_ID_FIREFOAM = 150)))         // replaces the 300 it inherits

CAPABILITIES(/obj/machinery/portable_atmospherics/powered/reagent_distillery)
	reagents(600, holder = /datum/reagents/distilling)
```

**Params.** `volume` (a number, `nameof(var)` read at init, or a `PROC_REF`), `starts`, `add`, `tint`, `holder`, `starts_from`.

**Inheritance.** A capability is one per type table; a subtype changes it with `configure()`, which rebuilds it from the inherited params
plus the named ones. Two params do not simply replace: `add` merges into the inherited `add` (amounts sum, the way every
`DECLARE_REAGENTS` line added to its parent's), and `starts` replaces the contents and drops inherited `add`s. The engine hook for this is
`/datum/capability/proc/reconfigure_ctor(ctor, changes)` (`code/engine/declare/capability_def.dm`): the default replaces each named
param; a capability whose param accumulates down a tree overrides it.

**Timing.** The holder is made in the capability's `on_holder_preinit()` hook, which runs at the root of `/atom/Initialize()`, exactly where
the declaration table ran (`lifecycle_decls_init()` calls `engine_holder_preinit()` first): a subtype's `Initialize()` sees the filled
holder right after `. = ..()`, a declared appearance can read it, and `reagent_container()`'s own init (later, in `caps_init()`) finds the
holder made and only adjusts its volume and adds its own `starts`.

**Memory.** One interned definition per distinct declaration (`cap_intern()`); an instance owns only its `/datum/reagents`.

**`reagents()` and `reagent_container()`.** `reagents()` is the holder and what it starts with, nothing else: use it on anything that
holds liquid (a mop, an organ, a machine's tank). `reagent_container()` brings the ops that move liquid (pour, fill, splash, drink, inject,
spray), the transfer-amount prompt and the fill look; it makes a holder itself when none exists.

## 3. Reagents and their effects as data (plan)

Today a reagent is a `/datum/reagent` subtype (about 1,300 of them) whose vars are its data (name, colour, metabolism, overdose, taste,
`factors`, `treatment_tags`, the species tables) and whose procs are its effects (`affect_blood/ingest/touch`, `overdose`, `touch_*`); a
holder instantiates one datum per reagent it contains. Much of the per-mob effect is already data: `factors` and `treatment_tags` are read
by the body (`accumulate_reagent_factors()`, `build_treatment_snapshot()`, dose bands in `code/modules/body/factors.dm`), and
`species_injuries_*` / `immune_species_*` are tables (P2-S13). The plan, in order:

1. **One definition per id.** `REAGENT_DEF` tables generated from the reagent types by `analyze gen` (`code/_generated/reagents.dm`):
   name, colour, state, metabolism, overdose, taste, glass look, export value, scannable, allergens, specific heat. The holder keeps only
   `id -> volume`, `id -> data` and the doses; the per-holder datum goes. Readers that take a `/datum/reagent` today read the definition.
2. **Effects are contributions, holds and doses.** What a reagent does while it is metabolised is declared on its definition:
   - a steady effect scaled by dose is `contributes(STAT_X, per_unit, band =)` from the reagent as source (the `factors` table, renamed when
     body factors become `STAT_*`, final_api section 5);
   - a status a reagent keeps up (`status_at_least(STAT_DROWSY, 20)` every cycle) is `hold(mob, STATUS_X, value, SRC_REAGENT(id), lasts =)`,
     released when the dose ends (`on_mob_end_metabolize()` already marks that edge);
   - an amount per unit (healing, injury, nutrition) is a `doses(INJURY_X | TREAT_X | NUTRITION, per_unit)` row the cycle applies with
     the uptake, in Rust when the body's ledger moves there;
   - what is left (an emote, a message, a mutation roll) stays a `then(PROC_REF(x))` on the definition, run by the cycle.
3. **The cycle on the body's clock.** Life's `life_chemicals()` calls `metabolize()` on the three holders today. The body owns organ work on
   its clock (`organ_clock()`, `organs_advance(cycles)`, `code/modules/body/body_clock.dm`); metabolism joins it as one more entry
   (`every(LIFE_CYCLE, then(chemicals_step), when = STAT_CHEMICALS_ACTIVE)`), scaled by the cycles of body time that passed like the organs,
   and the liver's and kidneys' clearance (`organ_tick()`) reads the same uptake. This moves with the Life owner (OM/Life), not here.

Each step is pinned by `dq_chem_metabolism_pin` and the reagent tests before it lands.

## 4. Chemistry maths in Rust: `vg-chem`

`verdigris/domains/chem` (host-buildable, no dependencies; `cargo test -p vg-chem`) holds the numbers every chemistry step runs. Like the gas
reaction energy (`verdigris/domains/gas/src/reaction_energy.rs`), DM decides *what* reacts or is metabolised and gathers the inputs, and Rust
computes *how much*. The maths is `f32` in DM's order, so the numbers are DM's.

**Reaction progress** (`reaction::progress`, bind `vg_chem_reaction_progress(limit, rate, multiplier, yield, result_amount, product_have,
min_reaction, reactants)`): one step of a reaction goes `limit * rate * multiplier`, capped by the yield limit (a reaction with yield
`y < 1` stops when product reaches `y / (1 - y)` of the reactants' reaction units), and completes when what it would leave of any reactant is
within `min_reaction` units of nothing. `calc_reaction_progress()` gathers `have, ratio` per reactant and calls it; `react_step()` still takes
`min(limit, progress)`, removes the reactants and adds the product (reagent `data`, belly tracking and the reaction's own hooks are DM's).

**Metabolism cycle** (`metabolism::cycle`, bind `vg_chem_metabolism_cycle(flat)`, 7 numbers in and `CHEM_CYCLE_OUT` = 5 out per reagent):
`/datum/reagents/metabolism/proc/metabolize()` first plans the whole cycle (`plan_cycle()`): the body's share of the rates once per holder
(`cycle_body()`: BF_METABOLISM, the holder's speed, the heart's pulse, the stomach and intestine, a machine's pump and cycler), each reagent's
own rate (`/datum/reagent/proc/cycle_rate()`: its metabolism or `ingest_met`/`touch_met`, the organs that filter it), then one Rust call
for every reagent's uptake (`min(rate, volume)`), dose, largest volume and overdose (`volume > overdose * species threshold`, and the base
injury `min(removed * mod * floor(3 + 3 * volume / overdose), 3.6)`). Each reagent's `on_mob_life()` then applies its own
(`cycle_taken()`), so the overrides that wrap it keep working. `overdose()` reads the cycle's injury (`overdose_injury`), or asks
`vg_chem_overdose_injury()` when called outside a cycle.

**Pins.** `code/modules/unit_tests/dq_chem_math_pins.dm`, recorded on the DM implementation before the move:
`dq_chem_reaction_progress_pin` (every reaction decl, reactants at 1, 4.3, 25 and 150 times their ratios, with and without product present:
5,800 rows) and `dq_chem_metabolism_pin` (a human, three holders, five cycles: volume and dose of each reagent). The start state of every
holder declared with the old macros is `dq_reagents_start_snapshot` (one row per type under each declaring root).

Next candidates, when a measurement says the call count matters: the whole `handle_reactions()` fixed point for a holder whose candidate
reactions are all plain (no `can_happen`/`on_reaction` override), and the heat a reaction releases (a reagent enthalpy table beside the
gas one).

## 5. Machines and chemistry still on legacy forms

`modules/reagents` machines keep interaction-era forms (`DECLARE_INTERACTIONS` rows with `REQ_*`, `INTERACT_SILICON`/`INTERACT_OBSERVER`,
`OM_FIELD`, `DECLARE_APPEARANCE_PROC`, `OM_EMIT`, `ITEM_INTERACT_*` returns): the chemical dispenser (`dispenser2.dm`), the chem master,
the grinder, the distillery, the synthesizer, the bunsen burner, the alembic, the injector maker, the pump, the chemalyzer, and the syringe's
`DECLARE_PERIODIC_WHILE`. Their conversion follows `conversion_guide.md` (behaviour pins first, then the block). Status per machine is
in `intended_changes.md` under "Reagents".

## 6. Codemod

`python tools/dx/codemods/reagents_decl.py [--check]` (rules: `codemod_rules.md`, "reagents"). It reads every declaration in the tree
first, so each type's entry is computed from its whole chain: a type with no declaring ancestor gets `reagents()`, a subtype gets
`configure(reagents(...))` with only what its own lines changed, and a type that dropped and re-declared gets `starts =`. The entry goes
under the type's existing `CAPABILITIES` header in any file, else the declaration line becomes a new block in place. It converted 698
declarations in 72 files with no residue; a second run finds nothing.
