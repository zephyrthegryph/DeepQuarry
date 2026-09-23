# Grants

One generic grant system so no subsystem reimplements "source X gives mob Y
thing Z". Lives in `code/datums/grants/`, kind ids in `code/__defines/grants.dm`.

## The problem it replaces

Before this, ABILITY had its own source-tracked, refcounted grant list on
`/mob/living` (`ability_grants`, `grant_ability()`/`revoke_ability()`), and
LANGUAGE had none at all - every caller that could independently add and
remove the same language (a translator module, a cult mark, a hivemind organ)
either didn't bother refcounting (so two sources fighting over one language
could strip it out from under the other) or invented its own ad-hoc tracking.
FACTORS had no way for a source outside `factors.dm`'s five hard-coded kinds
(affliction/reagent/modifier/species/trait/form/worn item) to contribute at
all. Three subsystems, three reimplementations (or missing implementations) of
the same idea: **N sources can independently claim to grant the same thing to
the same mob, and it should stay granted exactly as long as any of them do.**

## The API

```dm
grant(mob, kind, id, datum/source)    // source now grants id (a GRANT_KIND_*) to mob
revoke(mob, kind, id, datum/source)   // source no longer grants it
revoke_all(mob, datum/source)         // every grant `source` holds on `mob`, every kind
```

Both are **global procs**, not mob procs: granting is something a source does
*to* a mob, and keeping them global means `source` reads naturally as the verb's
subject rather than a bolted-on last argument. `mob` is the mob, `kind` is a
`GRANT_KIND_*` (below), `id` is whatever that kind uses to name what's granted
(a string/number id for ABILITY and LANGUAGE, the source's own factor table for
FACTORS - see kind_factors.dm), `source` is the datum that owns the grant.
**Sources are always datums, never strings** - a string can't be listened to
for `COMSIG_QDELETING`, so it can't be auto-revoked, and it can't disambiguate
two unrelated things that happen to pick the same name.

Reads:

```dm
mob.has_grant(kind, id)       // any source granting it right now?
mob.grant_sources(kind, id)   // the list of sources, for UI/debugging - never mutate it
grants_from(datum/source)     // every (mob, kind, id) `source` currently grants,
                               // as a list of /datum/grant_link - null if none
```

Storage is lazy: a mob with no grants allocates nothing (`/mob/var/list/grants`
stays null). The global source index (`GLOB.grant_source_index`) only holds an
entry for a source that currently grants something.

### Refcounting

Grants are refcounted **per (mob, kind, id) by distinct source**, not by call
count: granting the same `(kind, id, source)` twice is a no-op (idempotent),
and two different sources granting the same `(kind, id)` both have to revoke
before it goes away. The kind's `on_grant()` fires exactly once - when the
COUNT of sources goes 0 -> 1 - and `on_revoke()` fires exactly once, when it
goes 1 -> 0. Two traits granting the same ability, or an item and a species
baseline both contributing the same factor table, never fight each other and
never need the caller to track who else granted it.

### Auto-revoke on delete

Deleting a source revokes every grant it made, across every kind and every
mob, automatically - `grant()` registers the source for `COMSIG_QDELETING`
(the framework-level "this datum is going away" signal) the first time it's
used as a source, and unregisters it once it grants nothing. That hook lives
in **exactly one proc**, `/datum/grants_manager/proc/on_source_qdeleting()`
(`grants_core.dm`) - if the engine's Destroy/qdel architecture changes what
signals a deletion, that's the only place to retarget.

Whoever calls `grant()` still owns calling `revoke()` (or `revoke_all()`) when
their source *leaves* a mob without being deleted - unequip, uninstall, a
modifier expiring. Auto-revoke-on-delete is a safety net for the case that
matters most (forgetting on Destroy()), not a replacement for that discipline,
same as signals and components.

## Kinds

A **kind** (`/datum/grant_kind`, `grant_kind.dm`) is a singleton that says what
actually happens when a mob's `(kind, id)` grant count crosses 0<->1:
`on_grant(mob, id, source)` / `on_revoke(mob, id, source)`. Kinds register
themselves once (a bare `new` at file scope); `grant()`/`revoke()` look them up
by id and `stack_trace()` if nothing's registered for a kind.

| Kind | `GRANT_KIND_*` | `id` is... | on_grant/on_revoke does... |
|---|---|---|---|
| ABILITY | `GRANT_KIND_ABILITY` | an ability id (`code/__defines/abilities.dm`) | nothing - `why_not()` reads `has_grant()` live |
| LANGUAGE | `GRANT_KIND_LANGUAGE` | a `GLOB.all_languages` key | `add_language(id)` / `remove_language(id)` |
| FACTORS | `GRANT_KIND_FACTORS` | the source's own factor table (an `alist` of `BF_id -> value`) | `invalidate_factors()` + `life_wake()` |
| TRAIT | *(reserved, DQ Medical)* | - | - |
| GENE | *(reserved, DQ Medical)* | - | - |

### ABILITY

`code/datums/abilities/ability.dm`. Replaces the old `grant_ability()`/
`revoke_ability()`/`ability_grants` mob var entirely - deleted, not shimmed.
`has_ability(id)`/`ability_sources(id)` survive as thin one-line wrappers over
`has_grant(GRANT_KIND_ABILITY, id)`/`grant_sources(GRANT_KIND_ABILITY, id)`,
kept because `why_not()` and every caller read much better as
`L.has_ability(id)` than `L.has_grant(GRANT_KIND_ABILITY, id)` - they add no
logic, just a name.

```dm
grant(L, GRANT_KIND_ABILITY, ABILITY_ID_SHADEKIN_PHASE_SHIFT, SK) // SK is the source
revoke(L, GRANT_KIND_ABILITY, ABILITY_ID_SHADEKIN_PHASE_SHIFT, SK)
```

Migrated: `code/datums/components/species/shadekin/shadekin.dm` (the component
is the source), `code/modules/mob/living/silicon/robot/robot.dm` (every robot
grants itself `ABILITY_ID_ROBOT_TOGGLE_LIGHTS`), and the unit tests
(`dq_ability_tests.dm`).

### LANGUAGE

`code/modules/mob/language/language.dm`'s `add_language()`/`remove_language()`
stay the low-level, unconditional primitives - species defaults and one-shot
narrative grants that are never individually revoked still call them directly.
Use the grant instead whenever an item, implant, organ or modifier can
**independently add and later remove** the same language, so overlapping
sources don't strip a language out from under each other:

```dm
grant(L, GRANT_KIND_LANGUAGE, LANGUAGE_UNATHI, src)   // src is the granting module/organ/component
revoke(L, GRANT_KIND_LANGUAGE, LANGUAGE_UNATHI, src)
```

Migrated (found via `rg` for `add_language`/`remove_language` pairs tied to a
source that can go away independently of the mob):

- **pAI Universal Translator** (`code/modules/mob/living/silicon/pai/software_modules.dm`,
  `/datum/pai_software/translator`) - the explicit motivating case. Toggling it
  on/off now grants/revokes its whole language list keyed by the module
  instance, instead of 27 unconditional `add_language()`/`remove_language()`
  calls that didn't know or care whether something else also wanted one of
  those languages active.
- **Borer "Cortical Link"** on the host, granted when a borer bonds
  (`borer_control.dm`) and revoked on `detatch()` (`borer.dm`) - keyed by the
  borer mob. (The borer's own innate `add_language("Cortical Link")` on itself,
  `borer.dm` `Initialize()`, is permanent and untouched.)
- **Cult mark language** (`code/game/antagonist/station/cultist.dm`,
  `/datum/antagonist/cultist`) - granted in `add_antagonist()`, revoked in
  `remove_antagonist()`, keyed by the antag datum.
- **Xenomorph hive node organ** (`code/modules/organs/subtypes/xenos.dm`) -
  granted in `replaced()`, revoked in `removed()`, keyed by the organ.

**Left alone, on purpose:** the robot module language swap
(`code/modules/mob/living/silicon/robot/robot_modules/station.dm`,
`add_languages()`/`remove_languages()`) also snapshots and *restores* the
robot's pre-module language set (including the per-language speech-synthesizer
flag), which isn't a plain grant/revoke - converting it would either lose the
synthesizer flag or need the API to carry extra per-grant data it doesn't have
room for. Left as direct `add_language()`/`remove_language()` calls. Also left
alone: every one-shot `add_language()` at mob spawn/creation with no matching
removal (species defaults, AI/pAI/robot base kits, ghost-pod character
creation, `transform_procs.dm`) - there's no source to track because nothing
ever un-grants them.

### FACTORS

`code/modules/body/factors.dm`. Unlike ABILITY/LANGUAGE, a factor grant's `id`
**is** the contributed table (an `alist` of `BF_id -> value`, same shape as
`/datum/modifier/var/factors`) - there's no separate name for "a set of factor
contributions" the way `ABILITY_ID_*`/language names name a thing. An organ,
implant or item that isn't already one of `factors.dm`'s five built-in sources
uses this to fold a static table into body factors:

```dm
grant(L, GRANT_KIND_FACTORS, my_factors_table, src)
revoke(L, GRANT_KIND_FACTORS, my_factors_table, src)
```

`on_grant()`/`on_revoke()` only invalidate (`invalidate_factors()` +
`life_wake()`); the actual fold happens in `recompute_factors()`
(`factors.dm:244`), which now calls `accumulate_grant_factors()`
(`code/datums/grants/kind_factors.dm`) alongside the affliction/modifier/
reagent/plan accumulators already there. Each **distinct currently-granted
table** folds once per rebuild, regardless of how many sources grant it -
consistent with every other factors.dm source (an active modifier folds once,
not once per thing that re-applied it).

New factor ids for `rewrite/mobsrc` (`code/__defines/body_factors.dm`,
contiguous block right before `BF_ARMOR_BASE`, which shifted from 69 to 72):

- **`BF_ALPHA`** (70) - `BF_RULE_MULT`, baseline 1, bounds [0, 1]. A generic
  0..1 multiplier for grants that don't need a named factor.
- **`BF_MOVE_FLAGS_DENY`** (71) - `BF_RULE_FLAGS`, deny mask. Effective move
  flags = `base & ~factor(BF_MOVE_FLAGS_DENY)`; derive the mob var on
  `COMSIG_LIVING_FACTORS_CHANGED`, the same way `action_blocked()` derives
  blocked actions from `BF_ACTION_BLOCKS` - `rewrite/mobsrc` wires the actual
  consumer. Nothing here converts alpha or pushes a user of either factor;
  they're placeholders these two ids exist for.

The `factors.dm` edit is one line (the new
`acc = accumulate_grant_factors(acc)` call in `recompute_factors()`) plus two
new rows in `body_factor_defs()` - committed separately, since that file
belongs to DQ Medical.

### Adding a kind (TRAIT/GENE, DQ Medical)

1. Pick the next free id in `code/__defines/grants.dm` (`GRANT_KIND_TRAIT`,
   `GRANT_KIND_GENE`, ...).
2. Subtype `/datum/grant_kind` with `kind = GRANT_KIND_YOURS`, implement
   `on_grant()`/`on_revoke()` (see `kind_ability.dm` for the "do nothing, a
   reader checks `has_grant()` live" shape, or `kind_language.dm` for the
   "call a real setter/unsetter" shape).
3. `new` it once at file scope (`GLOBAL_DATUM_INIT` or a bare `new`).
4. `#include` the file in `deepquarry.dme` near the other `code/datums/grants/`
   files.

Nothing else needs to know the kind exists - `grant()`/`revoke()` find it by
id, and every mob-side helper (`has_grant`, `grant_sources`, `dump_grants()`,
the VV dropdown) already works for any kind.

## Holder semantics: body swap, resleeve, mind transfer

A grant's *source* decides who keeps it when a mind changes body:

- **Body-sourced** (an organ, implant or item): follows the BODY. It lives on
  whatever mob physically holds that source right now, so it needs no special
  handling at all - a mind moving to a different body doesn't touch it, and it
  naturally stops applying once the organ/implant/item leaves (unequip,
  uninstall, or the source itself being deleted, via the auto-revoke path).
- **Mind-sourced** (learned languages, species memory, anything granted with
  the mind datum itself as `source`): follows the MIND. `transfer_grants()`
  (`code/datums/grants/grants_transfer.dm`) moves it from the old body to the
  new one.

```dm
/proc/transfer_grants(mob/from, mob/to, filter)
```

Revokes every grant on `from` whose source `istype(source, filter)`, and
re-grants the same `(kind, id, source)` on `to` - which re-runs the kind's
`on_revoke()`/`on_grant()` on the correct mob each time (so ABILITY/LANGUAGE/
FACTORS all stay correct without special-casing). `filter = null` moves
everything, which is almost never what you want on a body-owning mob (see
above) - pass a type.

Wired into the one place every mind move already goes through,
`/datum/mind/proc/transfer_to()` (`code/datums/mind.dm`), which covers body
swap, resleeving and every other path that calls `transfer_mind()`/
`move_player_mind()`/`move_player()`:

```dm
transfer_grants(old_character, new_character, /datum/mind)
```

Any grant whose source `istype`s `/datum/mind` (the mind itself) moves;
everything else (the common case - organs, implants, items) stays exactly
where its physical source is. A source that grants through some OTHER
mind-owned datum (an antag holder, a learned-spell datum, ...) and needs to
ride along can call `transfer_grants()` again with its own type from its own
transfer hook - the call site in `transfer_to()` is a starting point, not the
only one that's allowed to exist.

## Admin surfacing

- **View Variables**: `grants` is an ordinary mob var, visible and editable
  like any other.
- **`dump_grants()`** (`code/datums/grants/grants_debug.dm`): human-readable
  dump grouped by kind and id, with sources named - callable from VV directly,
  or via the **"Dump Grants" VV dropdown option** on any mob
  (`VV_HK_DUMP_GRANTS`, `code/__defines/vv.dm`; wired in
  `code/modules/mob/mob.dm`'s `vv_get_dropdown()`/`vv_do_topic()`, same pattern
  as "Add Language"/"Add Organ").

## Tests

`code/modules/unit_tests/dq_grants_tests.dm`:

- refcounting across two sources (survives one revoking, gone once both have)
  and idempotent double-grants
- `on_grant()`/`on_revoke()` fire exactly once (0->1 / 1->0), not once per
  source, using a throwaway counting kind
- deleting a source auto-revokes its grants across ABILITY, LANGUAGE and
  FACTORS in one mob
- `has_grant()`/`grant_sources()`/`grants_from()` queries
- `revoke_all()` clears one source's grants on one mob without touching
  another mob it also granted to
- a FACTORS grant dirties the body and folds into `factor()`, and reverts on
  revoke
- a LANGUAGE grant with two overlapping sources
- holder semantics on `transfer_mind()`: a mind-sourced grant follows the mind
  to the new body, a grant from something else stays on the old body

`dq_ability_tests.dm`'s existing ABILITY refcount test was updated to call
`grant()`/`revoke()` directly instead of the deleted `grant_ability()`/
`revoke_ability()`.
