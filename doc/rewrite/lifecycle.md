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
| 4 | **Links.** Clear every declared relationship (§4): owned children deleted, pairs' other sides nulled, back-list memberships removed. | links framework | ~400 null/QDEL_NULL/pair bodies |
| 5 | **Teardown.** Stop every processor (START_PROCESSING records its subsystem on the datum); timers, reactor, components, signals and tgui (already in `/datum/Destroy`); `client.screen` release; OM timers and task steps owned by the datum (`om_teardown_rest`); arguments naming it are handles and stop resolving; grants auto-revoke (source lifetime). | core | ~150 stop/deltimer/unregister/close_uis bodies |
| 6 | **Effects.** Declared `destroy_effects` data: message, sound, debris type, neighbour update. | effects | ~60 effect bodies |
| 7 | **Destroy hook.** The type's `on_destroy(force)` (domain consequences only; always calls `..()`), then the core `Destroy()` chain (`/atom/movable`, `/atom`, `/datum`). A `Destroy()` override anywhere else is banned outright (`lifecycle_counts_lint.py`); the only other `Destroy()` definitions are `/client` and the MC's `/datum/controller` tree. The GC hint is the type's `destroy_hint` var. | type | every per-type `Destroy()` |
| 8 | **Scrub.** Null outbound declared owned and pair vars to break reference cycles, then hand the datum to GC. Nothing is parked in nullspace pending deletion. | links | cycle-breaking null-only bodies |

Around the phases:
- **Refusal** comes first. `lifecycle_keep(force)` returning TRUE (or
  `LIFECYCLE_KEEP_UNLESS_FORCED(type)` / `LIFECYCLE_KEEP_ALWAYS(type)`) makes `qdel()`
  leave the object whole, before phase 0 runs; it used to be a `Destroy()` returning
  `QDEL_HINT_LETMELIVE` after the object had already been half torn down.
- **Behaviours** get `/datum/om/behaviour/proc/on_destroy(E)` at the start of phase 4,
  after `lifecycle_prerelease()` and before the links clear, so the entity's declared vars
  still read; `on_stop(E)` follows in phase 5.
- **Handles mid-delete.** From phase 0 a handle accessor (`owner()` returning
  `om_resolve(owner_handle)`) reads null for the dying object, so `thing.owner() == src`
  is FALSE inside src's own teardown. Compare with `om_handle_is(thing.owner_handle, src)`,
  which matches until phase 5 releases the handle slot.

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

Every object-typed var on a datum is declared as exactly one of these kinds. A
lint derived from the L1 reference lint (`tools/ci/state_schema_lint.py`)
enforces it.

| Declaration | Semantics | Covers |
|---|---|---|
| **slot content** | lives in a ledger slot, with its policy per §3 | cells, parts, wires, occupants, organs |
| `REF_OWNED(var)` / `REF_OWNED_LIST(var)` | a child that is not contained (actions, loops, helpers, DB/tgui contexts), deleted in phase 4 | `QDEL_NULL`/`QDEL_LIST` bodies |
| `REF_PAIR(var, other_var)` | two-sided. Set and cleared only through `link_set()`/`link_clear()`, and destroying either side nulls the other | sleeper↔console, portals, teleporter, turbolift doors, card_slot holder |
| `REF_BACKLIST(var, list_var)` | membership in another object's list (assoc or plain), removed automatically | `projector.signs`, aim lists, implant DB |
| `REF_DEF(var)` | a frozen definition or registry object that is never deleted (`/datum/material`, `/datum/decl`, a techweb design, an uplink category). Destruction does nothing with it. A var whose declared type is in `DEF_TYPES` (`tools/ci/state_schema_lint.py`: material, decl, language, property_def) is an implicit `REF_DEF` and needs no declaration; species are not in it, because `produceCopy()` makes per-mob copies | material, flooring, closet appearance, designs, uplink categories |
| `REF_TRANSIENT(var)` | a pooled object's per-use field (§4.1). `pool_release()` resets each to its initial value from the declaration, so no hand-written clearing can leak a reference. Scalars may be listed too. The lint accepts it only on a `POOL_DECLARE`d type | damage packet `source`/`attacker`/`weapon` |
| OM handle | a text var holding `om_handle(x)`, resolved with `om_resolve(h)` (null once `x` is deleted). Replaces `/datum/weakref` ([object_model_core.md §4.11](object_model_core.md#411-one-scheduler-time-sequences-and-asynchrony)) | "remember who it was": last attacker, forensics, logs, UI selections, tgui and client refs, saved IDs |
| declared cache | `declared_cache_vars()` maps the var to its invalidation rule: `CACHE_ON_CHANGE(bits)`, `CACHE_ON_EVENT(path)` or `CACHE_ON_RELATION(path)` (`code/__DEFINES/om.dm`). The OM core nulls the var when the rule fires (a raise of those channels, an event of that type, an edge of that relation added or removed); scrubbed in phase 8 | caches |

- **LC-refs.** Every datum-typed instance var or list is exactly one of: a
  relation or slot, an owned child, an OM handle, a declared cache with an
  invalidation rule, a `REF_DEF` definition reference, or a `REF_TRANSIENT` field of
  a pooled type. There is no "weak" kind any more: `/datum/weakref` goes
  away, live links become relations and everything else becomes a handle.
  The LC-refs lint (`tools/ci/scheduler_lints.py`) counts undeclared vars and is
  ratcheted to 0. `GLOB` lists of objects become OM registries, which drop
  deleted members.
- **LC-refs: lists.** The same rule covers what an instance list *holds*. A list
  var that gets objects as keys or values (`L[obj] = ...`, `L[key] = obj`,
  `L += obj`, `L |= obj`, `L = list(obj = ...)`) must be declared: an owned-children
  list (`declared_owned_list_vars()`), the list side of a backlist (named by some
  `declared_backlist_vars()`), or a declared cache. Otherwise it becomes a relation,
  a registry, or is keyed by `om_handle()`. `tools/ci/declared_refs_lint.py` finds
  these writes syntactically (an object is `src`, `usr`, a `new` expression or a
  name the proc declares object-typed) and ratchets them per file in
  an outright ban (the ratchet reached 0; a justified write carries `// ALLOW(object_keyed_lists): <reason>`).
- **LC-refs: cache rules.** A `declared_cache_vars()` entry without a
  `CACHE_ON_*` rule fails the lint outright (no ratchet), and the core reports one
  at runtime when the type first joins the OM (`om_cache_scan()`). The rule is read
  once per type into its type table; change rules add their bits to the entity's
  listen mask so the raise reaches the core, which clears the cache before any
  other dispatch.
- Medical, body, organs, afflictions, surgery, protean and Life are in the
  sweep like everything else (§7). Their mapping: body `REF_OWNED` from the
  mob; afflictions and the clock schedule `REF_OWNED_LIST`; organs as slot
  content (O2); mind via `mind_host` `TRANSFER`.
- Per-type relationship tables are **precomputed at boot**, following the
  pattern of `registries_by_type`, so phase 4 is a table walk with no `vars[]`
  reflection.
- Generic nulling runs **after** leftover `Destroy()` (phase 8). Legacy code
  that reads its own refs during Destroy still works, and code that does
  `qdel(x); x.foo` in the same tick isn't broken mid-call.

### 4.1 One-place declarations and pools

**`REF_VAR`.** A var and its kind can be declared together, in one line next to
the type (`code/__defines/lifecycle.dm`). The older `REF_*` forms keep working.

```dm
// Before
/datum/component/geiger_sound
	var/datum/looping_sound/geiger/sound
...
REF_OWNED(/datum/component/geiger_sound, "sound")

// After
REF_VAR(/datum/component/geiger_sound, OWNED, /datum/looping_sound/geiger, sound)
```

`KIND` is any single-name kind (`OWNED`, `OWNED_LIST`, `OWNED_VALUES`, `SPILL`,
`SPILL_LIST`, `HELD`, `DEF`, `TRANSIENT`); `VARTYPE` is the full type (`/list` for
list kinds). `REF_PAIR_VAR(PATH, VARTYPE, NAME, "other")` and
`REF_BACKLIST_VAR(PATH, VARTYPE, NAME, "list_var")` cover the two assoc kinds.

**Pools** (`code/datums/lifecycle/pool.dm`). A scratch object made and dropped on
a hot path (the damage packet, one per hit) is pooled instead:

```dm
POOL_DECLARE(/datum/damage_packet)
REF_TRANSIENT(/datum/damage_packet, list("source", "attacker", "weapon", "zone", "penetration", "direction", "flags", "armor_flag"))

var/datum/damage_packet/packet = pool_take(/datum/damage_packet)
...
packet.release()   // or pool_release(packet)
```

- `pool_take(type)` hands out a free object or makes one; `pool_release(obj)` resets
  the `REF_TRANSIENT` fields and returns it to the per-type free list.
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
behaviour's `on_destroy(E)`. Otherwise they go in the type's `on_destroy(force)`.

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
| LC2 | Links framework: `REF_OWNED`/`REF_PAIR`/`REF_BACKLIST`, boot-time tables, `link_set`/`link_clear`, the declared-reference lint and its ratchet | ledger-joint |
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
