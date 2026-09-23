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
| 5 | **Teardown.** Stop every processor (START_PROCESSING records its subsystem on the datum); timers, reactor, components, signals and tgui (already in `/datum/Destroy`); `client.screen` release; clock callbacks (DQ Medical `w6/k1`: `clock_teardown(datum)` cancels callbacks owned by and targeting the datum); grants auto-revoke (source lifetime). | core | ~150 stop/deltimer/unregister/close_uis bodies |
| 6 | **Effects.** Declared `destroy_effects` data: message, sound, debris type, neighbour update. | effects | ~60 effect bodies |
| 7 | **Leftover `Destroy()`.** Only domain consequences remain. Linted: an override must justify itself with a `// LIFECYCLE:` reason, and the count is ratcheted. | type | — |
| 8 | **Scrub.** Null outbound declared owned and pair vars to break reference cycles, then hand the datum to GC. Nothing is parked in nullspace pending deletion. | links | cycle-breaking null-only bodies |

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
| weak (`datum/weakref` typed var) | the default for everything else. Resolved on read and never cleaned | all incidental refs |
| `tmp` cache | recomputable, and scrubbed in phase 8 | caches |

- The lint allow-lists DQ Medical areas (body, organs, afflictions, surgery,
  protean) until they convert. Their planned mapping: body `REF_OWNED` from the
  mob; afflictions and the clock schedule `REF_OWNED_LIST`; organs as slot
  content (O2); mind via `mind_host` `TRANSFER`.
- Per-type relationship tables are **precomputed at boot**, following the
  pattern of `registries_by_type`, so phase 4 is a table walk with no `vars[]`
  reflection.
- Generic nulling runs **after** leftover `Destroy()` (phase 8). Legacy code
  that reads its own refs during Destroy still works, and code that does
  `qdel(x); x.foo` in the same tick isn't broken mid-call.

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

These are preferably written as a `COMSIG_QDELETING` handler owned by **the
other party**, the pattern grants already uses (the relationship's owner watches
the lifetime; the dying object doesn't clean up after itself). Otherwise they
are a justified `Destroy()`.

## 7. DQ Medical areas

Medical, body, organs, surgery, protean, species and mob Life are **not**
converted under this plan. DQ Medical plugs into the same phases:
- body part slots (w6/o2) use per-slot policies with children-first order;
- the mind/brain `TRANSFER` resolver is declared by body plans;
- clock-scheduled callbacks (w6/k1) expose one teardown entry point, called in
  phase 5;
- O4 (body destroy ordering) builds on §3.

This design is sent to DQ Medical for review before code lands.

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
