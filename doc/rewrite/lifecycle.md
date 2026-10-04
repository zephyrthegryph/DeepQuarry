# Lifecycle: destruction is a framework transaction

Status: **authoritative**. This replaces J1 ("pre-destroy phase", superseded
commit `ebbcf9adb2` on `rewrite/ledger-joint`) and the destruction parts of
`containment.md` and `state.md` where they disagree.

## 1. Goal and numbers

Per-type `Destroy()` and ad-hoc `qdel()` should almost disappear. Destruction
becomes one transaction that frameworks own. Types **declare** their
relationships, slots, bindings and effects, and no cleanup is written by hand.

Master today:
- **~1,190** non-test `Destroy()` overrides;
- **~3,070** gameplay `qdel(` sites, of which 1,241 are `qdel(src)`.

What those overrides do (sample of 85):

| Share | What the override does |
|---|---|
| 32% | delete owned children |
| 21% | null references only |
| 20% | clear links, pairs or holder back-references |
| 12% | leave registries or globals |
| 11% | stop processing or timers |
| 6% | spill contents by hand |
| 6% | release UI |
| 5% | unregister signals |
| 4% | play destruction effects |
| 2% | Rust unbind |
| ~5% | real domain logic |

About **200 overrides are already redundant** with base types:
- 80 only call `..()`;
- 109 call `STOP_PROCESSING(SSobj)`, which `/obj/Destroy` already does;
- 20 call `close_uis(src)`;
- 13 call `UnregisterSignal(src…)`;
- most timer-handle `deltimer` calls.

`/datum/Destroy` already clears timers, reactor subscriptions, components,
signals and tgui.

Targets:
- **≥ 85%** of overrides removed. The ~120–180 that remain are real domain
  consequences.
- About **half** of gameplay `qdel` sites replaced by verbs (§5).
- Both counts are **ratcheted by CI lint**, the way C11 ratchets raw `contents`
  access.

## 2. The transaction

`qdel(D)` runs `destroy_transaction()` (`SHOULD_NOT_OVERRIDE`) before any
leftover `Destroy()`. The phases run in a fixed order, and that order is the one
place the ordering hazards now scattered through code comments are encoded:

| # | Phase | Owner | Replaces |
|---|---|---|---|
| 0 | **Guard.** Set `gc_destroyed`, send `COMSIG_QDELETING`, mark `DESTROYING`. From here `QDELETED(src)` is true, which stops pair and partner loops. | garbage | paicard/pAI-style hand guards |
| 0.5 | **Mind.** Resolve every `TRANSFER(mind)` slot in the whole holder tree, **pre-order** (outermost first: body mind slot before head, before brain), while the mob is still fully registered and has a `loc`. Ghost/MMI spawn here. | containment ledger + body plan resolver | ghostize/MMI transfer in Destroy |
| 1 | **Unbind.** Every R10 entity binding (`vg_entity_unbind`), heat bodies and pipe/cable topology, through the declared `bindings`. Must precede dematerialize. | vg bindings | ~20 atmos/heat Destroy blocks and the hard-ordered heat release in `/atom/Destroy` |
| 2 | **Dematerialize.** Leave registries (L3) and drop rule bindings, as today. Every remaining `GLOB.x += src` moves into a registry declaration. | registries | ~72 list removals |
| 3 | **Contents.** Resolve every slot's **declared destroy policy** (§3). This is depth-first post-order through nested holders: children before parents. No holder-managed or leftover `contents` loops remain. | containment ledger | hand spills, `QDEL_LIST` of parts, machinery `component_parts` loops, the movable `contents` sweep |
| 4 | **Links.** `lifecycle_prerelease()`, the type's `on_destroy()` and behaviours' `on_entity_destroy(E)`, then dispose of every owned value by policy and clear every relation on both ends (§4, [archive/ownership.md](archive/ownership.md)). | links framework | ~400 null/QDEL_NULL/pair bodies |
| 5 | **Teardown.** Stop every processor (START_PROCESSING records its subsystem on the datum); timers, reactor, components, signals and tgui (already in `/datum/Destroy`); `client.screen` release; OM timers and task steps owned by the datum (`om_teardown_rest`); arguments naming it are handles and stop resolving; grants auto-revoke (source lifetime). | core | ~150 stop/deltimer/unregister/close_uis bodies |
| 6 | **Effects.** Declared `destroy_effects` data: message, sound, debris type, neighbour update. | effects | ~60 effect bodies |
| 7 | **Core `Destroy()`.** The core chain (`/atom/movable`, `/atom`, `/datum`). A `Destroy()` override anywhere else is banned outright (`lifecycle_counts_lint.py`); the only other `Destroy()` definitions are `/client` and the MC's `/datum/controller` tree. The GC hint is the type's `destroy_hint` var. | type | every per-type `Destroy()` |
| 8 | **Scrub.** Null outbound declared owned and pair vars to break reference cycles, then hand the datum to GC. Nothing is parked in nullspace pending deletion. | links | cycle-breaking null-only bodies |

Around the phases:
- **Refusal** comes first. `lifecycle_keep(force)` returning TRUE (or
  `LIFECYCLE_KEEP_UNLESS_FORCED(type)` / `LIFECYCLE_KEEP_ALWAYS(type)`) makes `qdel()`
  leave the object whole, before phase 0 runs; it used to be a `Destroy()` returning
  `QDEL_HINT_LETMELIVE` after the object had already been half torn down.
- **The destroy hook.** The type's `on_destroy(force)` (domain consequences only; always
  calls `..()`) runs at the start of phase 4, after `lifecycle_prerelease()` and before
  the links clear: contents are resolved, but relation views, owned children
  and handles still read, so it can reach its owner and partners.
- **Behaviours** get `/datum/om/behaviour/proc/on_entity_destroy(E)` right after it, also
  before the links clear, so the entity's declared vars
  still read; `on_stop(E)` follows in phase 5.
- **Views mid-delete.** From phase 0 the dying object is `QDELETED`, but its relation views and
  its partners' views of it stay set until phase 4, so `on_destroy()` can still read them.

**No nullspace parking** (DQ Medical requirement): the transaction never moves
an atom to nullspace to "finish later". Contents resolve in phase 3 while the
holder still has a `loc`, so TRANSFER and SPILL have a live destination.

## 3. Slot destroy policies

Every slot declares one policy. `SLOT_DROP_HOLDER` (left to the holder's
Destroy) is **removed**.

| Policy | Meaning |
|---|---|
| `SPILL` | move contents to the holder's turf (forced; J2) |
| `DELETE` | contents destroyed in the same transaction (recursively, children first) |
| `TRANSFER(resolver)` | a declared proc picks a destination. Examples: mind → ghost or MMI, a pilot ejected to a turf, a bellied mob to the pred's turf |
| `TO_LATENT` | contents stay as latent entries on a declared successor (for example debris or wreckage) |
| `KEEP_WITH(slot)` | move into another slot of the successor in `replace_with()` (§5) |

- **Nested holders** (limb trees, organs in limbs, items in bags in bags)
  resolve **children before parents**. Each child's own slots resolve first,
  within the same transaction.
- **Mind and brain before the body** (DQ Medical requirement). `TRANSFER(mind)`
  slots resolve in **phase 0.5, pre-order** across the whole tree, before any
  registry drop and before the post-order walk reaches head→brain (which may
  carry `mind_host`). The body plan declares the resolver (ghost or MMI).
  Everything else resolves **post-order** in phase 3.
- **Hooks during destruction.** Every slot move made by the transaction passes
  `LEDGER_MOVE_DESTROYING`, and `holder_destroying(holder)` is queryable.
  `on_unslotted` hooks (J6) must skip re-derivation (body invalidate,
  life_wake, HUD, factor recompute) when it's set.
- **Gib vs qdel.** Policies are static per slot. Gib is `ledger_empty(SPILL)`
  on the part slots followed by `qdel`. There is no per-transaction
  disposition override.
- **Occupant slots** (C8a: mecha pilot, DNA scanner, sleepers) use
  `TRANSFER(eject_to_turf)`. The ledger-joint audit found two holders whose own
  `go_out()` ejection ran against an already-emptied slot. With this design
  ejection *is* the slot policy, so that ordering bug can't occur.
- Latent entries use the same policies as pure data.
- `DELETE` of a latent entry never materializes it, and `SPILL` of many latent
  entries is budgeted.

## 4. Declared references

Every object-typed var is one of own / shared / proto / relation. The model, its accessors,
declarations and checks are specified in [archive/ownership.md](archive/ownership.md); this section only says how
the transaction uses it.

| Phase | What ownership does |
|---|---|
| 0 | the dying entity refuses new timers, hooks, tasks and relation links |
| 2 | a dying owned entity leaves its owner's var (`own_release_from_owner()`) |
| 3 | `OWN_SPILL` movables still inside drop to the holder's drop location (`own_spill_phase()`) |
| 4 | every owned var is disposed of by policy (`own_teardown()`), private proto copies are deleted, then relation views clear on both ends (`rel_teardown()`) and rich edges are unlinked (`om_teardown_links()`) |
| 8 | an owned var re-set during teardown is deleted and reported (`own_scrub()`) |

- Most declarations are implicit: a var written with `own_*` is owned (`OWN_DELETE`), one written
  with `rel_*` is a relation view, one typed as a registry type is shared. Declared: `OWN(...,
  OWN_SPILL / OWN_CONTAINED)`, `OWN_POLICY`, `OWN_IF`, `PROTO`, `SHARED`, `REL_PAIR`,
  `REL_PAIR_LIST`, `REL_SET`, `REL_KEYED`, and the annotations `KEEP_AFTER_DESTROY`,
  `POOL_RESET`, `FORWARD_STATE` (`code/__defines/ownership.dm`).
- Hand-written clean-up of declared things in `on_destroy()` / `lifecycle_prerelease()` is
  redundant and goes; only real domain consequences stay.
- Declared caches (`declared_cache_vars()` with a `CACHE_ON_*` rule) are unchanged.

### 4.1 Pools

A scratch object made and dropped on a hot path (the damage packet, one per hit) is pooled
(`code/datums/lifecycle/pool.dm`):

```dm
POOL_DECLARE(/datum/damage_packet)
POOL_RESET(/datum/damage_packet, source)
POOL_RESET(/datum/damage_packet, attacker)
...

var/datum/damage_packet/packet = pool_take(/datum/damage_packet)
...
packet.release()   // or pool_release(packet)
```

- `pool_take(type)` hands out a free object or makes one; `pool_release(obj)` resets
  the `POOL_RESET` fields and returns it to the per-type free list.
- Releasing an object that isn't taken crashes (double-release detection).
- Pooled objects refuse a normal `qdel()` (`POOL_DECLARE` overrides `Destroy()`).
- Poisoning, `pool_set_poison(TRUE)` (tests and debugging): a released object is
  marked `POOL_STATE_POISONED` and never handed out again, and `POOL_ASSERT_LIVE(src)`
  at the top of the type's procs crashes on it, catching use after release.
- `om_diagnostics()["pools"]` (`pool_diagnostics()`) reports free, out, peak,
  created, taken, released, double releases, poisoned, use-after-release and
  refused qdels per pooled type.

## 5. Replacing qdel call sites

| Verb | Replaces |
|---|---|
| `consume(item, actor)` | removes from the slot, then destroys. Replaces the 117 `drop_from_inventory(x); qdel(x)` sites and matches interaction `item_use` and `CONSTRUCTION_ITEM_DELETE` |
| `replace_with(path, …)` | creates the successor at the same loc or slot, carries over declared state and contents via `KEEP_WITH`/`TO_LATENT`, destroys the original. Replaces the 175 `new X(); qdel(src)` sites and deconstruction debris |
| `lifetime = N` / `expire(after)` | effects, projectiles, spawners and helpers. Replaces the ~90 timed deletes and most `qdel(src)` in effects |
| `slot_clear(slot)` / `ledger_empty(policy)` | replaces the 143 qdel-in-loop owned-children sites |
| `delete_on_death` declaration | death-driven deletion (spores, shades). Subscribes to the final hook of DQ Medical's ordered death pipeline (O5), never to stat changes. The destroy transaction never calls `death()` |

`qdel()` remains the engine underneath these verbs. Direct calls outside the
frameworks are linted and ratcheted.

## 6. What legitimately stays per-type

Real consequences outside the object's declared relationships, such as:
- a pAI dying with its card;
- a cursed weapon punishing its wielder;
- a looking-glass program unloading.

These are preferably written as a qdeleting hook owned by **the
other party**, the pattern grants already uses (the relationship's owner watches
the lifetime; the dying object doesn't clean up after itself), or as a
behaviour's `on_entity_destroy(E)`. Otherwise they go in the type's `on_destroy(force)`.

## 7. Medical, body, organs, surgery and Life

These areas are **not** excluded: the session that owns the lifecycle work also
owns medical, body, organs, surgery and Life, so every sweep (LC-refs, the
qdel and Destroy() ratchets, weakrefs) includes them. They use the same phases:
- body part slots (w6/o2) use per-slot policies with children-first order;
- the mind/brain `TRANSFER` resolver is declared by body plans;
- clock-scheduled callbacks (w6/k1) are OM timers (`om_after`), cancelled in
  phase 5 with the rest of the record;
- O4 (body destroy ordering) builds on §3.

## 8. Plan

| Step | Scope | Owner |
|---|---|---|
| LC1 | `destroy_transaction()` in `qdel` with phases 0–8; `SLOT_DROP_HOLDER` removed and policies for every slot; nested children-first resolution; `TRANSFER(resolver)`; processor recording and auto-stop; screen release | ledger-joint (replaces J1) |
| LC2 | Links framework (superseded by the ownership model, [archive/ownership.md](archive/ownership.md): own / shared / proto / relations, `ownership_lint.py`) | ledger-joint, own |
| LC3 | Verbs: `consume`, `replace_with`, `lifetime`/`expire`, `slot_clear`, `delete_on_death`, plus the `destroy_effects` data | ledger-joint |
| LC4 | Mechanical sweeps: delete the ~200 redundant overrides; convert overrides and qdel sites domain by domain; ratchet the lints to the floor | conversion agents, after the core systems land |

Tests (written now, run when the testing freeze lifts):
- phase ordering;
- children-first nested resolution;
- mind transfer before body deletion, including a brain inside a head inside a body, destroyed from the body (pre-order, fully registered, has a loc);
- `LEDGER_MOVE_DESTROYING` passed to every hook during the transaction;
- occupant ejection;
- pair symmetry on both-sides destroy;
- re-entrancy (a partner destroyed inside our transaction);
- no nullspace parking;
- a zero-leak check across a mass-delete (explosion-sized batch);
- per-phase destroy time from `SSgarbage` before and after.

## 9. Starting state: the foundation forms of the lifecycle declarations [built]

What an instance starts with is declared in the three tables, not in `DECLARE_*` lines
(`code/__defines/lifecycle_decl.dm`, which stay until the codemod has moved their sites). All of it happens at
the end of `/atom/Initialize()`, so a subtype's `Initialize()` sees it right after `. = ..()`, exactly as with
the macros: starting occupants in `lifecycle_decls_init()` (step 1, before gas and reagents), the capabilities in
`caps_init()` right after, the `after_init()` timers in `rx_enrol()`.

| Declaration | Form | Implementation |
|---|---|---|
| Starting occupant (was `DECLARE_DEFAULT_CHILD`) | `relations()`: `rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))`. `starts` is a type, a list (`list(/obj/x = 2)`) for `rel_many`, or `nameof()` a var holding either, so a map or subtype override of `cell_type` picks the type. The var itself wins: a path in it (a map edit) is made instead, an instance in it makes nothing. The relation's `policy` decides teardown. | `owns(starts =)` is an annotation in the ownership table (`own_table.start_vars`), made by `own_init_starts()`. `DECLARE_DEFAULT_CHILD` is gone: its sites are `owns_one` / `owns_many` entries with `starts =` (a CONTAINED part keeps `owns(policy = OWN_CONTAINED, starts =)` in `ownership()` until it is a slot), and a `starts = PROC_REF(x)` returns what the var starts with (types, instances, or key = instance). The APC's cell is the worked example (`apc.dm` relations; a hand-built frame sets `cell_type = null` before `..()`). |
| Reagents (was `DECLARE_REAGENTS*`, `DECLARE_REAGENT_FROM_VAR`, `DECLARE_NO_REAGENTS`) | `capabilities()`: `reagents(volume, starts = list(...), holder =, tint =, starts_from =)`; a subtype adds with `refine(CAP_REAGENTS, starts = ..., volume = ...)` (added to the inherited contents, the macro's rule), drops it with `. = without(., CAP_REAGENTS)`. | `/datum/capability/reagents` (`library/reagents.dm`); `refine()` on a capability that is not an op calls its `refined(overrides)`. One interned flyweight per distinct declaration; an instance owns only its `/datum/reagents`, as before; a type without the capability allocates nothing. Worked example: the reagent tanks (`reagent_tank.dm`: the base `reagents(5000)`, each tank `refine(CAP_REAGENTS, starts = ...)`). |
| Login verbs (was `DECLARE_LOGIN_VERB`) | `type_verbs()`: `. += type_verb(/mob/proc/x, login = TRUE)` | `capabilities/type_verbs.dm`: the composed list is split per type (`type_verbs_always()` / `type_verbs_login()`); the verb store applies login entries at Login and refuses them on a mob no player has had. `DECLARE_LOGIN_VERB` is a thin wrapper. Worked example: `/mob/living`'s player verbs (`mob/living/login.dm`). |
| Gas (was `DECLARE_GAS`) | `capabilities()`: `gas_store(nameof(air_contents), volume, temp, list(GAS_X = kPa))` | `library/gas_store.dm`: owns the var (`owned()`), makes the mixture at init. Worked example: the transit tube pod. |
| Registry membership (was `DECLARE_REGISTRY`) | `capabilities()`: `membership(joins = REGISTRY_X)`; `joins` may list registry ids and `/datum/system` types | `library/membership.dm`: registry ids join `type_registries()` (so materialize joins, dematerialize leaves), a conditional registry is joined at materialize too; system types are the capability's `joins`. Worked example: the tape recorder. |
| Start timer (was `DECLARE_START_TIMER`) | `reactions()`: `after_init(delay, PROC_REF(x))`; `delay` may be `nameof(var)` | `reactions/after_init.dm`: armed by `rx_enrol()` at init (the boot list marks the type `RXB_INIT`), an ordinary `rx_after()` on the holder. Armed at init where the macro armed at materialize: a latent (unmaterialized) instance's timer runs too. Worked example: the broken gun's self-check. |

**DECLARE_BEHAVIOUR audit** (4 real sites):

| Site | Behaviour | Foundation form |
|---|---|---|
| `clothing/suits/utility.dm` radiation hood and suit | `radiation_protected_clothing`: a trait while attached, an examine line | `cap_trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = RADIATION_CLOTHING_EXAMINE)` **(converted; the behaviour is deleted)** |
| `clothing/shoes/miscellaneous.dm` dry galoshes | `dry`: on `before/shoes_step_action`, dries the floor and blood underfoot (never vetoes) | an after-fact: `on_notice(/datum/notice/<step>, PROC_REF(dry_floor))` once G3 generates the step notice (batch A1) |
| `mob/living/living.dm` `/mob/living` | `spontaneous_vore`: vetoes `before/stumbled_into`, `falling_down`, `hit_by_thrown`, `cross` | `before_op` on the G3 guard keys (stumble, falling, thrown hit, cross; batch A1) |
| the lifecycle test probe | test fixture | none needed |

**DECLARE_BIND audit:** no real site (only the test probe). A Rust binding is `push_to_rust()` with its generated
`rust_push()` reads for data, and a relation (or `lifecycle_unbind()`, the APC's node) for its lifetime.
`DECLARE_SERVICE_MEMBER` has no site; its form is `membership(joins = /datum/system/x)`.

**Codemod notes (A4).** `DECLARE_DEFAULT_CHILD` -> the relation's `starts` (merge into an existing `rel_one` /
`owns` of the var, else add `owns(nameof(v), policy = OWN_NONE, starts = ...)`). `DECLARE_REAGENTS*` per chain: the
chain root (no declaring ancestor) gets `reagents()`, each stacked declaration `refine(CAP_REAGENTS, starts =)` (with
`volume =` when it names one); never convert part of a chain. `DECLARE_LOGIN_VERB` lines of one type become one
`type_verbs()` override.
