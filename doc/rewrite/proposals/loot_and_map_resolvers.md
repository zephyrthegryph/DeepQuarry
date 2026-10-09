# Proposal: loot tables and map resolvers under capability entries

Status: **approved** (October 2026). Implemented on `rewrite/loot`.

Decisions (the questions in section 5, answered by the user):

1. Strict reading: `DECLARE_LOOT` and `MAP_RESOLVER` both move into `CAPABILITIES` entries (`loot(...)`, `map_resolver(PROC, vars =)`).
2. Option A first (entries build today's `/datum/loot_decl`, the roll engine unchanged), then Option B for the searchable piles (search is an
   `op("search", ...)` with `needs`/`wait`/`rolls`/`then`; the per-searcher state becomes a keyed stat).
3. The 38 pure `/loot/...` tables become abstract types with ordinary `CAPABILITIES` blocks. There is no `LOOT_TABLE_DEF`.
4. The full roll snapshot pin (306 declarations x 20 seeds) is committed.

Sections 2 to 4 below are the proposal as written; where the implementation differs, section 6 says how.
Scope: `DECLARE_LOOT` (306 sites, 39 files) and `MAP_RESOLVER` (34 sites, 30 files). Counts are from the `[lint.legacy_forms]` table in
`tools/ci/lint_scopes.toml` and `git grep` on master.

## 0. The design says two different things

`doc/rewrite/final_api.html` is not consistent about these two forms, so the first decision is what "move under capability entries" means.

- §6 ("Random spawns") and §17/§18 list `DECLARE_LOOT`, the `LOOT_*` rows, `loot_spawn()`, `loot_search()` and `MAP_VAR` as **kept** ("already declarative").
- §6 ("Map load") and §17 say `MAP_RESOLVER` becomes the entry `map_resolver(PROC_REF(x))` in the type block ("renamed").
- The legacy-forms table in `tools/ci/lint_scopes.toml` and the task for this lane say both are "capability entries (slated)".

This proposal takes the stricter reading (both become entries in the type's `CAPABILITIES` block) and costs the "keep it as is" reading as option 0.

## 1. The current forms

### 1.1 `DECLARE_LOOT`: a spec list next to a type

`code/__defines/loot.dm` expands `DECLARE_LOOT(PATH, SPECS...)` to `/datum/loot_decl<PATH>/specs()`, a proc that merges the specs over the
parent's (`loot_merge_specs`). `loot_decl_for(path)` builds one shared `/datum/loot_decl` per path, lazily, and caches it
(`code/datums/loot/loot.dm`). There are 306 declaration types.

A spawner (`/obj/random`), whose declaration lives in the same file:

```dm
// code/game/objects/structures/flora/flora.dm
DECLARE_LOOT(/obj/random/pottedplant, LOOT_TABLE(\
	/obj/structure/flora/pottedplant = 10, \
	/obj/structure/flora/pottedplant/large = 10, \
	/obj/structure/flora/pottedplant/fern = 10, ...
```

A spawner with a hook that post-processes what it made from the spawner's own map var edits:

```dm
// code/game/objects/random/mob.dm
DECLARE_LOOT(/obj/random/mob/<spawner>, LOOT_TABLE(... /mob/living/simple_mob/animal/passive/bird/parrot = 3),
	LOOT_HOOK(GLOBAL_PROC_REF(loot_hook_random_mob)))
/proc/loot_hook_random_mob(atom/spawned, path, list/varedits, datum/loot_rng/rng)
```

A pure table that is not an atom (`/loot/...` is a made-up path, referenced with `LOOT_REF`), with search tiers for loot piles:

```dm
// code/datums/loot/tables/trash.dm, maint.dm
DECLARE_LOOT(/loot/maint/junk, LOOT_TABLE(/obj/item/flashlight/flare, ...), LOOT_UNCOMMON(10, ...), LOOT_RARE(2, ...), LOOT_UNLUCKY(...))
// a pile names its table with the /obj/structure var loot_decl = LOOT_REF(/loot/maint/junk)
```

Shape of the rows (master, excluding unit tests): `LOOT_SUB` 331, `LOOT_SET` 304, `LOOT_UNCOMMON` 23, `LOOT_RARE` 21, `LOOT_DEPLETION` 20,
`LOOT_PER_ROUND` 11, `LOOT_TYPES` 10, `LOOT_HOOK` 8. 273 declarations are on `/obj/...` paths, 38 on pure `/loot/...` tables, none on mobs, turfs or datums.

Callers outside the macro: `loot_spawn(path, loc, varedits, rng)` (landmarks, falling objects, contraband, `/obj/random` resolution),
`loot_search(source, searcher, searched_by, wake_chance)` (loot piles, trash piles).

### 1.2 `MAP_RESOLVER`: a var on the type naming a proc

`MAP_RESOLVER(PATH, PROC)` expands to `PATH{map_resolver = PROC}`; `MAP_RESOLVER_VARS(PATH, "a;b")` names the map var edits to capture.
The proc is `proc(atom/loc, path, list/varedits)`, returns TRUE when it consumed the atom and FALSE to have the atom made normally.
It is called from two places (`code/modules/maps/map_resolvers.dm`):

- the map reader, before instancing (`map_resolve_path()`: reads `initial(path.map_resolver)`);
- `SSatoms.InitAtom()` for atoms BYOND already instanced (the compiled station map) and runtime `new` (`map_resolve_instance()`): the atom is detached, never initialized.

Real examples:

```dm
// code/game/objects/effects/decals/warning_stripes.dm  (an overlay on the turf)
MAP_RESOLVER(/obj/effect/decal/warning_stripes, GLOBAL_PROC_REF(resolve_warning_stripes))
/proc/resolve_warning_stripes(atom/loc, path, list/varedits)
	var/obj/effect/decal/warning_stripes/P = path
	... image(MAP_VAR(P, varedits, icon), icon_state = MAP_VAR(P, varedits, icon_state), ...)

// code/game/machinery/telecrystal_storage.dm  (a stack of N, into the closet on the tile)
MAP_RESOLVER(/obj/tcspawner, GLOBAL_PROC_REF(resolve_tcspawner))
MAP_RESOLVER_VARS(/obj/tcspawner, "amount_to_spawn")

// code/datums/loot/loot.dm  (the join: every /obj/random is a resolver that calls loot_spawn)
MAP_RESOLVER(/obj/random, GLOBAL_PROC_REF(resolve_loot))
```

The two forms meet in `/obj/random`: its resolver is `resolve_loot`, and a loot table entry that has "a declaration or a map resolver of its own" nests.
That is why they are one proposal.

### 1.3 What must not change (the contract)

1. **Determinism.** A map-time roll is seeded from `GLOB.loot_seed` mixed with `(x, y, z, type hash)` (`loot_rng_at()`, modulus `LOOT_HASH_MOD` so the
   products stay exact in BYOND floats). It does not depend on the order atoms are resolved in. Only runtime rolls (after `INITIALIZATION_INNEW_REGULAR`)
   also mix `GLOB.loot_roll_serial`. A round's map loot is reproducible from its seed.
2. **Table order.** `pick_entry()` walks the table in declaration order against cumulative weights, so the order of entries in a list is part of the result.
   Child declarations merge over the parent's; "what spawns" (table, all, per_round) is replaced as one unit.
3. **`LOOT_PER_ROUND`** fixes the first roll once per round per declaration, keyed by path.
4. **A resolved atom is never initialized or qdel'd**, on both paths (reader and InitAtom).
5. Resolvers run inside map loading and must not sleep.

## 2. Options for the target form

Common to all options: the type's inheriting `CAPABILITIES(T)` block carries the declaration, a subtype changes an inherited declaration with
`configure(...)` (the same word `reagents()` already uses), and the runtime (`/datum/loot_decl`, `loot_rng`, `loot_spawn`) stays.

### Option A: entries that build today's declaration (recommended for step 1)

`loot()` is an entry with the same row vocabulary, as sub-entries; `map_resolver()` is an entry. The entry builds the same shared `/datum/loot_decl`
for the owner type when the type's table is built. Pure tables become a named declaration line, because they have no type to hang an entry on.

```dm
CAPABILITIES(/obj/random/pottedplant)
	loot(table(
		/obj/structure/flora/pottedplant = 10,
		/obj/structure/flora/pottedplant/large = 10, ...))
	map_resolver(GLOBAL_PROC_REF(resolve_loot))      // inherited from /obj/random; written once there

CAPABILITIES(/obj/random/mob)
	loot(table(...), hook(GLOBAL_PROC_REF(loot_hook_random_mob)))

LOOT_TABLE_DEF(maint/junk,                            // pure table: a declared identifier (doc §1 "Declared identifiers")
	table(/obj/item/flashlight/flare, ...),
	uncommon(10, ...), rare(2, ...), unlucky(...))

CAPABILITIES(/obj/structure/pile/maint)
	loot_search(loot = LOOT_REF(maint/junk), left = 3, delete_on_depletion = TRUE)

CAPABILITIES(/obj/tcspawner)
	map_resolver(GLOBAL_PROC_REF(resolve_tcspawner), vars = list("amount_to_spawn"))
```

- Pros: nearly mechanical (a codemod like `tools/codemods/declare_emag.py`), no change of behavior, the golden roll pin in §4 proves it.
  Inheritance gets the doc's block semantics for free.
- Cons: still a side table (`/datum/loot_decl`) keyed by type, so "loot" is a second registry beside the capability table.
  `LOOT_TABLE_DEF` is a new declaration form for the 38 pure tables.

### Option B: loot as parts of ops (spawn is an action, search is an op)

A spawner is `spawns(...)` parts on an `after_init` / map-load hook, and a searchable pile is an `op("search", ...)` with `needs()`, `wait()`
and a `rolls(table)` part, so the search tiers become ordinary op steps (a raccoon waking is `then()`, depletion is a stat).

```dm
CAPABILITIES(/obj/structure/pile/maint)
	op("search", hand(), needs(req(PROC_REF(not_depleted))), wait(3 SECONDS),
		rolls(LOOT_REF(maint/junk), tiers = list(unlucky, uncommon(10), rare(2)), per_searcher = TRUE),
		then(PROC_REF(maybe_wake_raccoon)))
```

- Pros: the search path stops being a bespoke proc (`loot_search()`, 80 lines) and gets requirements, refusals, waits and tests like any op;
  `loot_spawn` becomes a part, so a machine's output slot, a crate fill and a spawner share one roll.
- Cons: a new part type plus its determinism plumbing (a part has no coordinate, so the rng key has to be chosen: holder position vs act id);
  `loot_search` has per-searcher state (`searched_by` ckeys) that has to move to a keyed stat; larger blast radius than A. Do it as step 2 on top of A.

### Option C: data files (tables out of DM)

Tables become `strings/loot/*.toml` or `.json` loaded at boot; the type only says `loot("maint/junk")`.

```toml
[maint.junk]
table = ["/obj/item/flashlight/flare", { path = "/obj/item/cell", weight = 3 }, ...]
uncommon = { chance = 10, entries = [...] }
```

- Pros: 300+ line path lists stop being code; server owners could tune a table without a rebuild.
- Cons: loses compile-time path checking (a typo is a runtime error, a rename is silent), needs a new lint to cover it, `LOOT_TYPES(subtypesof())`
  and hooks do not fit data, and the map-time determinism now also depends on file load order. It also contradicts the design's rule that
  content is declared next to its type. Not recommended.

### Option 0: keep as is

Honours §6/§18 literally and costs nothing, but leaves 340 uses of two macro families that are neither a capability entry nor a part, outside every
migration rule (no `configure`, no section grouping, no layering check). The legacy-forms table says "slated", so this needs an explicit "no" from the user.

## 3. Recommendation

Option A now, Option B later for searchable piles only; reject C.

Why: the risk in this migration is entirely in two properties (the seeded rolls and the resolve-before-init rule), and A is the only option that changes
neither while still removing the macro forms. It also leaves the semantic upgrade (search as an op) as a separate, separately testable change, instead
of coupling it to a 340-site rewrite.

Resolver specifics for A:

- `map_resolver(PROC)` writes the same per-type value that `initial(P.map_resolver)` reads today. The reader and `InitAtom()` must find it without an
  instance and before any `CAPABILITIES` table has been built for that type, so the entry builds a small per-type resolver cache (type to proc, vars)
  at world setup (before the first map load), not lazily inside the load. If it stays lazy, the first resolver call per type builds a table in the
  middle of a load, which is a mapload-ordering risk (see below).
- `MAP_RESOLVER_VARS` becomes the `vars =` argument; `MAP_VAR(P, varedits, name)` is kept (the design keeps it).
- Three types name `resolve_loot` (`/obj/random`, `/obj/effect/spawner/parts`, `/obj/effect/spawner/onetankbomb`); they become one entry each. The other
  ~30 resolvers name their own procs, which are real code and stay as they are; only the one-line declaration moves.

## 4. Migration plan

1. **Pin first.** Add a pin test before touching anything: for every declaration (306) and 20 fixed seeds, roll 50 times through `loot_spawn` into a
   scratch turf with `GLOB.loot_seed` set and record the sorted type list per (declaration, seed). Commit the snapshot (`doc/rewrite/snapshot_pins.md`).
   For search tables, the same through `loot_search` with a fixed rng. Add a second pin for the map reader: load one fixture template containing every
   resolver type and record what it leaves. The migration is only done when both pins are byte-identical.
2. **Engine entries.** `loot()`, `loot_search()`, `map_resolver()` and `LOOT_TABLE_DEF` land in `code/library/` (not the engine: it may not reference
   content). `/datum/loot_decl` and `loot_rng` move with them, unchanged. No call sites change in this commit.
3. **Codemod waves** (a `tools/codemods/declare_loot.py` and `map_resolver.py`, in the pattern of `declare_emag.py`), by directory so they can be
   proven separately: `code/game/objects/random/` (the bulk), `code/datums/loot/tables/`, then the singles. A file that has `DECLARE_LOOT` on a type
   with no `CAPABILITIES` block gets one; a file that already has a block gets the entry added to it (one block per type).
4. **Delete.** When the last caller goes: delete `DECLARE_LOOT`, `LOOT_*` row macros, `MAP_RESOLVER`, `MAP_RESOLVER_VARS`, `loot_merge_specs`; ban them in
   `[lint.legacy_forms.lists] banned` in the same commit. Update `final_api.html` §6/§17/§18 to the chosen reading.
5. **Later (Option B):** `loot_search()` to an op, behind its own pin.

### Risks

| Risk | Where it bites | Mitigation |
|---|---|---|
| Seeds change | The entry builds the hash differently, e.g. keying `loot_type_hash` off a different path string (`/datum/loot_decl/obj/random/x` vs the owner type) | Keep `loot_type_hash(path)` on the spawner's own type; the seed pin catches any drift |
| Table order changes | `CAPABILITIES` inheritance composes parent entries first and child entries after; today a child's line replaces `table` as one unit | `configure(loot(table(...)))` replaces, a plain `loot()` in a child is an error; codemod emits `configure` for every subtype that had its own line; pin catches order |
| Mapload ordering | Building a type's capability table inside the map reader runs entry code (`subtypesof()` for `LOOT_TYPES`) mid-load, when the type tree and globals are in an uncertain state, and recursion (a table entry that is itself an `/obj/random`) builds the nested type's table inside the first | Build the resolver and loot caches at world setup, before the first load, from the type list; nested lookups never build, they read |
| Runtime vs map-time rolls | `loot_roll_serial` is mixed in only after init (`INITIALIZATION_INNEW_REGULAR`); a new entry that rolls from a different phase would add it to map rolls and break reproducibility | The rng helper stays the only place that decides; test: a map-time roll with the same seed twice is equal, a runtime pair on one tile differs |
| `per_round` picks | `round_picks` is keyed by path on the shared decl; two declarations merged into one entry key could share a pick | Key stays the spawner's type; pin covers a `per_round` table |
| Resolve-before-init | The compiled station map is instanced by BYOND before our code runs; `InitAtom()` reads `map_resolver` off the instance. If the value moves into a table, an atom of an unregistered subtype resolves late or not at all | Keep the cached per-type lookup keyed by `A.type` with inheritance resolved at setup; unit test that every subtype of every resolver type resolves |
| Hidden dependencies | `resolve_landmark` calls `loot_spawn` (costume landmarks); `loot_spawn` consults "a map resolver of its own" for nested entries | Pin the nested case explicitly; keep `loot_spawn` the single entry point |
| Size of diff | ~340 sites, several 300-line tables | Pure move by codemod, tables untouched; reviewers diff the pin, not the tables |

## 5. Decisions needed

1. Take the strict reading (both become capability entries), or Option 0 (keep `DECLARE_LOOT` and `MAP_VAR`, as §6/§18 say) and convert only `MAP_RESOLVER`?
2. If strict: Option A with B as a later step (recommended), or go straight to B for the searchable piles?
3. Pure tables (`/loot/...`, 38): a `LOOT_TABLE_DEF(name, ...)` declaration line, or make each one a real (abstract) type so they are ordinary `CAPABILITIES(T)` blocks?
4. May the pin snapshot (306 declarations x 20 seeds) be committed? It is roughly 6k lines; the alternative is a hash per declaration (306 lines, but a failure
   no longer shows what moved).

## 6. How it was built (differences from sections 2 to 4)

- **Static entries.** A loot table or a resolver belongs to a type that is never made, so `declared_entries()` (an instance proc) cannot hold it. A kind marked
  `STATIC_ENTRY(kind)` (`loot`, `loot_search`, `map_resolver`) is left out of the instance chain by `analyze gen declare` and written into
  `declared_static_blocks()` instead; the `static_entries` kernel system (`code/engine/declare/static_entries.dm`) compiles those blocks once at world setup,
  parents first, before the first map load (the atoms and mapping systems need it). `configure(kind(...))` is merged by the kind's `/datum/entry_engine`
  (`merge()`), a plain second declaration of a singleton kind is an error, and each kind builds its cache from the finished tables (`static_built()`): the
  loot declarations by type, the per-type resolver table. Nested lookups only read.
- **`loot()` is named parameters**, not sub-entries: `loot(table =, count =, chance =, all =, hook =, per_round =, unlucky =, uncommon =, rare =, gamma_chance =,
  depletion =, repeat_search =)`. A subtype's `configure(loot(...))` replaces the parameters it names; what spawns (`table`, `all`, `per_round`) is one unit, as
  `loot_merge_specs` made it. The row constructors take a list (`loot_set(weight, list(...))`, `loot_sub`, `loot_tier(chance, list(...))`): a variadic proc
  loses the weight of a `/path = weight` argument, a list keeps it.
- **Pure tables** are abstract `/loot/...` types; there is no `LOOT_TABLE_DEF`. `loot_type_hash()` hashes the text the declaration type had
  (`/datum/loot_decl/loot/...`) for them, so the seeds did not move.
- **`loot_search(table =, wake_chance =)`** names a pile's table (the old `loot_decl` var and the argument the trash pile passed). The roll proc that used to be
  called `loot_search()` was renamed for the entry (`loot_pile_search()`, then `loot_search_roll()`).
- **Resolvers.** The `/atom` `map_resolver` and `map_resolver_vars` vars are gone: `GLOB.map_resolvers` holds, for every type under a declaring one, its
  `/datum/map_resolver_info`; `SSatoms.InitAtom()` looks the instance's type up in it.
- **Waves** were closed under inheritance (a legacy declaration does not inherit from an entry), by `tools/codemods/declare_loot.py` and `map_resolver.py`; both
  forms were read until the last site went, then deleted and banned (21 names) in one commit.
- **Pins** (`code/modules/unit_tests/snapshots/loot/`): the rolls (`rolls.txt`, 6120 rows), the pile searches, the resolver table (every atom type that resolves)
  and the map-reader fixture (`resolver_fixture.dmm`). Recording them needed a null guard in the repair droid (the rolls delete uninstalled ones), and left out of the
  fixture the stairs spawner, the turbolift holder, `/obj/random`, `/obj/effect/spawner/parts` and `newbomb` (a base spawner with no table recurses forever, a mapped
  TTV bomb runtimes during a load; the table pin covers their resolvers).
- **Option B** (search as an op, `code/library/loot/loot_search.dm`): see `doc/rewrite/intended_changes.md`, "Loot piles: the search op".
