# Typed values: an honest declaration for a var that holds a type path, a message path, text or a number (proposal, 2026-10-25)

Status: proposal for user review. Doc only; no code. Numbers are `origin/master` on 2026-10-25.
Related: `proposals/relations.md` D8 (the `untyped` lint), `proposals/base_vars.md`, `proposals/hot_base_vars.md`.

## 1. Problem

DM declares a var's type only with an atom or datum path: `var/obj/item/x`. `var/text/x`, `var/num/x` and `var/path/x` do not compile (BYOND
rejects an undefined type; DreamChecker and `tools/dmb` agree). So a var that holds **a type path** (`debris_type`, `fish_type`, `has_item_product`,
`material_template`), **a refusal reason** (a `/datum/msg` path, or a text) or **a plain value that an unknown call computes** has no declaration at all
and is written `var/x`, which the ref lints read as "may hold an entity":

- the `untyped` lint (`tools/analyze/src/lints/untyped_refs.rs`) reports an untyped var assigned an atom or datum (`typed`) or the result of a call
  the model cannot type (`call`), because the value "may be an entity";
- a base-type var of this kind has no `base_vars` home until the value's kind is declared: a trait field, profile field or sparse slot needs a typed
  schema, and none exists for "a path under `/obj/item/stack`";
- reads cannot be typed: `new fish_type(loc)` yields an untyped local, so the relations lints lose the object downstream.

## 2. Census

`tools/ci/untyped_baseline.txt` on `origin/master`: **116 rows**, 109 `call`, 7 `typed`. Classified by what the var holds (by name and a reading of the
assigned expression; the lane re-derives it with the analyzer):

| Kind | Rows | Examples (file:line on master) |
|---|---|---|
| A type path | about 10 | `/obj::debris_type` (`code/game/objects/obj_defense.dm:5`, read at `:137`, `list((debris_type) = amount)`), `/turf/simulated/floor/water::fish_type` (`code/modules/fishing/fishing.dm:67`, assigned `pickweight(rare_fish_list)` at `:112`, read `new fish_type(...)` at `:102`), `/datum/seed::has_item_product` (`hydroponics/seed.dm:32`), `/datum/xform::material_template` (`library/transformations/transformation_entry.dm:180`), `/datum/design_techweb::material_template` (`research/tg/designs.dm:39`), `/datum/expedition_mission::faction_type` (`expedition/expedition_mission.dm:33`), `/datum/event_meta::event_type` (`events/event.dm:13`), `/obj/structure/blob/core::desired_blob_type` (`blob2/blobs/core.dm:12`), `/mob/living::body_type` (`body/body.dm:16`, default `/datum/body/simple`) |
| A refusal reason, a `/datum/msg` path (or text) | 6 | `/datum/act/action::reason` (`code/contracts/acts/context.dm:54`, "a /datum/msg type"), `/datum/op_result::reason` (`:146`), `/datum/op_cand::dropped_reason` (`engine/parts/resolve.dm:37`), `/datum/prompt/choice/record_update_review::initial_refusal`, `/datum/request::last_error`, `/datum/act/action::reply`; assigned `unknown.reason = /datum/msg/op/unknown` (`engine/parts/run.dm:130`), `refused.reason = op_resolution_refusal(R)` (`:160`) |
| A text or number from a call the model cannot type | about 90 | ids and tags (`/obj/machinery/air_sensor::id_tag`, `/obj/machinery/camera::c_tag`), tones and frequencies (`/obj/item/pda::ttone`, `/datum/signal::frequency`), names and messages (`/datum/event_meta::name`, `/datum/article::headline`), counters and amounts (`/obj/item/integrated_circuit/reagent/pump::transfer_amount`, `/datum/reagents::maximum_volume`), keys (`/datum/mind::assigned_role`, `/mob::faction`, `/mob/living/silicon/robot::modtype`) |
| An entity-shaped assignment (`typed`) | 7 | `/obj/item/implant::implanted`, `/obj/item/hand::parentdeck`, `/datum/vore_preferences::spont_belly_*`: these are real references and belong to the relation forms, not here |

`base_vars` rows blocked on a value declaration (a path-valued var on a base type, where the home is a trait field that needs a typed schema): `/obj::debris_type`,
`/mob/living::meat_type` (`mob/living/butchering.dm:4`), `/obj/item::identity_type` (`game/objects/items.dm:79`, default `/datum/identification`),
`/mob/living::say_list_type` (`combat_ai/legacy_constants/say_list.dm:10`), `/mob/living::footstep_type` (a `FOOTSTEP_*` text). Five rows of 238.

Scale beyond the baselines: 414 `var/x = /some/path` lines (a var with a path default, untyped) and 943 vars named `*_type`. Most are not in the baseline because their
assignments are literals the lint types as values; the declaration is for the ones whose assignment is a call, a `pickweight`, or a list read.

## 3. What already exists

The vocabulary and the runtime check are on master; what is missing is the lints reading them.

- **`SCHEMA(T, V, expr, opts...)`** (`code/__defines/engine/declare.dm:87`): "the same schema for a var that is not tracked and is declared on its own line". It
  attaches a value schema to `T`'s var; `schema_of(type, var_name)` finds it down the type chain (`code/engine/declare/schema.dm:219`). One site uses it today
  (`code/tests/engine/e1_fixtures.dm:199`).
- **Schema kinds** (`schema.dm:1-12`): `bool()`, `int()`, `num()`, `enum()`, `flags()`, `schema_text()`, `schema_ref(type)`, **`schema_path(type)`** (a type path that
  descends from `type`, `schema.dm:122`), `list_of()`, `map_of()`, `row()`. `schema_check()` / `schema_write()` check a value at a boundary.
- **`MSG(path)`** (`declare.dm`): `/datum/msg/<path>`, the declared message types (950 references on master). A requirement returns null to allow or a message path to refuse
  (AGENTS section 3a).
- `analyze`'s declaration scan already lists `SCHEMA` as a marker (`tools/analyze/src/sem/decls.rs:27`); `gens/ui_types.rs` reads it for UI field types.
- Compiler acceptance: `SCHEMA(...)` is an ordinary statement of macro-generated procs (`T/proc/__schema_V()` and a `/datum/schema_decl` subtype). No new syntax, so
  DreamMaker and `tools/dmb` accept it as they accept `TRACKED_SCHEMA`.

What the `untyped` and `stored_refs` lints do with it today: nothing. A var with a `SCHEMA` is still an untyped var.

## 4. Options considered

| Option | Verdict |
|---|---|
| `var/path/x`, `var/text/x`, `var/num/x` | Does not compile. |
| DM's `as` clause on a var (`var/x as path`) | `as` takes input types (`num`, `text`, `mob`, `obj`, ...), and `path` is not one of them. Even where it parses, it cannot say "a path under `/obj/item/stack`", and DreamChecker gives it no meaning. Rejected for paths; to confirm for text and num with a 5-line probe in the lane (both compilers), but it would add nothing the lints can read. |
| A typed-path macro on the var line (`PATH_VAR(/obj/item/stack, debris_type)` expanding to `var/debris_type`) | A second declaration form beside `SCHEMA`, a macro that hides a `var/` from every textual tool, and it cannot carry text/num/msg. Rejected. |
| A `/datum/msg` instance instead of a path (a flyweight, `var/datum/msg/reason`) | Honestly typed with no new form, but every `return /datum/msg/x` in the `req_*` library and every `reason =` becomes a call; about the whole refusal channel changes for a typing win. Held as an alternative (D2). |
| **`SCHEMA(T, V, schema_expr)` read by the analyzer** | Chosen. The form exists, the schema vocabulary exists, one kind of declaration for every value, and the check at the boundary (a UI arg, a request, a loaded record) already runs. |

## 5. Proposed form

```dm
/obj
	var/debris_type
SCHEMA(/obj, debris_type, schema_path(/obj/item/stack))

/turf/simulated/floor/water
	var/fish_type
SCHEMA(/turf/simulated/floor/water, fish_type, schema_path(/obj/item/fish))

/datum/act/action
	var/reason
SCHEMA(/datum/act/action, reason, schema_msg())
```

New schema kinds (small engine change, `schema.dm`):

- `schema_msg()`: null, a `/datum/msg` path, or (decision D2) a text. `schema_check` reports a path that is not under `/datum/msg`.
- `one_of(schema, ...)` only if D2 keeps text-or-msg; otherwise `schema_msg()` alone covers reasons.
- `schema_text()` and `num()`/`int()` already exist and serve the text and number rows.

Analyzer model: `sem` records a per-var `Decl::value_schema(kind, base)` from the `SCHEMA` marker, found down the owner chain as `schema_of` does. Then:

1. **`untyped`**: a var with a value schema is a value, never an entity; its assignments are not sites. The lint **checks** them instead: an assigned path literal must descend
   from `schema_path`'s type (`debris_type = /obj/item/foo` where `/obj/item/foo` is not a stack is a finding); a message assignment must be a `/datum/msg` path; a call result
   is trusted (the declaration is the author's claim, and the runtime check below backs it).
2. **`dm::value_procs`** (the fixpoint of procs whose every return is a number, text or null): extend it to path literals and `cond ? /a : /b`. This needs no declaration at all
   and is the first, free step: it clears every `call` row whose right side is a proc that returns paths, which is every `req_*` refusal (`library/requirements/*.dm`,
   `return /datum/msg/op/busy`). The count is measured, not guessed, in the first lane.
3. **`stored_refs`**: a var with a value schema is not a reference; the lint skips it. This also clears the untyped-list false positives for `list_of(schema_path(...))`.
4. **`base_vars`**: a var with a value schema may be a trait or sparse field: the trait constructor's argument names its schema (`obj_defense(debris_type = /obj/item/stack/rods)`),
   so the five blocked rows get their homes.
5. **Typing reads**: analyze types `new X(...)` where `X` is a var with `schema_path(B)` as `B`, so the object a `fish_type` makes is typed downstream. DreamChecker cannot see it; the
   analyzer can, and it is the one that judges `stored_refs`.
6. **Runtime check**: `schema_check` runs at every boundary already. A unit test `dq_typed_values_defaults_fit` walks every type that has a `SCHEMA` and checks `initial(var)`
   against its schema (one pass over the type tree, normal tier). A plain `debris_type = x` write is not checked at run time, like any plain var; the lint checks literals, the test
   checks defaults.

Cost note: `SCHEMA` generates a proc and a `/datum/schema_decl` subtype per var. Roughly a hundred declarations add about a hundred small types; the lane measures compile time and
type-table size before converting the long tail, and if it is visible, adds a block form `values()` in `CAPABILITIES` that records the same schema without a type (decision D3).

## 6. Migration

1. **`value_procs` path returns** (free, no source change): measure the baseline drop.
2. **Analyzer reads `SCHEMA`** and the four lint changes; `schema_msg()` in the engine. Fixtures: a path literal outside the base, a message path, a `pickweight` assignment.
3. **`analyze fix` proposes the declaration**: for an `untyped` `call` row it infers the schema (a literal default's kind, the common base of the assigned literals, `schema_text()`
   when every assignment is a text, `num()` otherwise) and writes the `SCHEMA` line; a human reviews the base type of each path (the machine cannot know that `fish_type` is
   `/obj/item/fish`). `analyze baseline --update --lint untyped` drops the rows.
4. **Reasons** (`reason`, `reply`, `dropped_reason`, `initial_refusal`, `last_error`) in one commit with `schema_msg()` (they are the engine's own files: one lane).
5. **Base-var homes** for the five rows once their schemas exist (`proposals/base_vars.md` wave).
6. **Ban**: a new `untyped` row is refused as now; the hint changes from "type it as a value" (impossible) to "declare `SCHEMA(T, v, ...)`".

Risks: a wrong base type in `schema_path` rejects a legitimate subtype at a boundary (the UI arg) and fails the lint on a valid literal; the fix proposes, a reviewer chooses. A var
with several kinds (a reason that is sometimes text) needs D2 settled first. Subtypes that override a var's default keep the schema (it is found down the chain).

## 7. Decisions (DECIDED 2026-10-25, the coordinator on the user's delegation)

- **D1, decided yes.** Use the existing `SCHEMA(T, V, expr)` and teach the analyzer; no new declaration form.
- **D2, decided: `/datum/msg` paths only, plus `msg_text()`** (`code/engine/parts/part.dm:640`) for run-time text. `schema_msg()` has one kind; the few text reasons are converted by hand. The flyweight
  instance alternative is not taken.
- **D3, decided: measure first.** Compile time and type-table size are measured before the long tail converts; a `values()` block entry is added only if the per-var `/datum/schema_decl` types show up.
- **D4, decided: propose only.** `analyze fix` writes a proposed `schema_path` base for review and never applies it.
