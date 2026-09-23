# Containment (track C)

One system owns where everything is. It covers:
- mob inventory and equipment, and held items;
- storage and closets;
- machine internals and occupants;
- mechs;
- vore bellies;
- vending and smartfridge stock;
- circuit assemblies;
- reagents, as a fluid store behind the same API.

Today these are about a dozen separate systems.

## 1. Today

| System | How it works now | Problems |
|---|---|---|
| Storage | Old Polaris `/obj/item/storage` (`code/game/objects/items/weapons/storage/storage.dm`) | `can_be_inserted` re-adds every item already inside on each call; `handle_item_insertion` relies on `usr`; 2–4 screen objects are created eagerly per storage (~6–8k atoms at roundstart); `orient2hud` rebuilds a slot atom per item |
| Mob inventory | One typed var per slot, spread across mob types (`l_hand`, `w_uniform`, `wear_suit`, …) | `u_equip` is an if/else chain; `equip_to_slot` sets `loc` directly, so `Entered` never fires; `slot_in_backpack` skips storage insertion; `get_equipped_items` misses pockets and suit storage; robots edit `contents` directly |
| Pickup | `/obj/item/attack_hand` (`items.dm:337`) | Four separate steps with no rollback: `remove_from_storage`, `pickup()`, `unEquip`, `put_in_active_hand`. `stall_removal` can sleep in between. |
| Vore | `/obj/belly` objects inside the owner, holding real contents via `forceMove` | Heavy `Entered`/`Exited`. SSbellies processes every belly every 6 s, including empty ones, which allocate a new list each time. About 240 vars and 58 lists per belly, 45 of them message lists. |
| Machine occupants | A typed `occupant` var plus `forceMove`; some use weakrefs; the suit storage unit has named slots | About 18 copies of go-in/go-out code; the sleeper's eject skips the beaker, board and parts |
| Mechs | `occupant`, `equipment`, `internal_components` and `cargo` all mixed in one `contents` | Six roles in one list |
| Closets | `starts_with`, spawned in `LateInitialize` | 699 mapped closets spawn about 5.4k direct items, roughly 10k+ atoms including nested contents |
| Vending | `/datum/stored_item`, virtual until the first vend | Then materializes the product's whole amount (fixed in C9: stock slots) |
| Circuits | Plain `contents` of an assembly | Pin datums built eagerly; one instance of all ~195 circuit types at boot |
| Movement | `doMove` calls `Crossed`/`Uncrossed` on every atom in both locations, including a full bag, closet or belly; `onTransitZ` recurses through all contents | Cost grows with everything carried |

## 2. The ledger

Every move goes through one API, which enforces five invariants.

1. **One owner each.** Everything has exactly one owner: a turf, a slot on a holder, or a pool. Latent entries carry IDs with generations, so a UI holding a stale entry is rejected rather than acting on one that was merged or removed.
2. **Moves are transactions.** `move(thing, to_slot)` checks both sides first (can it be removed, can it be inserted, is there capacity), then commits both, then fires the hooks. A failed check leaves everything where it was, and nothing that can sleep runs between check and commit. Materializing an entry is also a ledger move, so nothing can be materialized twice.
3. **Destroying a holder is generic.** The base `/atom/Destroy()` applies each slot's drop policy to real and latent contents alike: drop, destroy, or transfer. No type's own `Destroy()` decides what happens to contents.
4. **Merging and splitting happen only in the ledger.** Entries are keyed by type, variant and delta hash ([state.md §4](state.md#4-deltas)). Inserting a collapsible item increments a matching entry, and changing one of N splits it off. Gameplay code never merges anything.
5. **The ledger keeps aggregates.**
   - Mass, heat capacity, minimum thresholds and capability flags are updated incrementally on every insert and remove, for real and latent children alike.
   - When a child's own property changes, the change bubbles up once per tick through reactor events.
   - Debug builds periodically recompute everything and compare.

`forceMove` goes through the ledger whenever a slot holder is involved. Raw `loc =` and `contents +=`/`-=` writes (about 595 today) are converted and then forbidden by lint.

### 2.1 As built (C1)

The code is in `code/datums/containment/`; defines are in `code/__defines/containment.dm`.

- **API** (`api.dm`):
  - `thing.move_into(holder, slot_id, actor)` inserts. A null `slot_id` means the default slot.
  - `holder.slot_remove(thing, destination, actor)` takes a thing out. If the destination has slots, it's a transfer.
  - `holder.slot_transfer(thing, new_holder, slot_id, actor)` moves a thing from one holder's slot to another.
  - `holder.slot_empty(slot_id, destination)` empties a slot.
  - `dq_ledger_refusal(thing, holder, slot_id, actor)` returns the reason a move would fail, or null.
  - Reads: `slot_contents`, `slot_used`, `slot_capacity`, `contents_property(id)`, `contents_has_tag(tag)`, `slot_entry_id(thing)` and `slot_find_entry(id)`.
- **Checks before the commit.** The source slot's `removal_refusal()` and `COMSIG_SLOT_PRE_REMOVE` run first. Then the destination slot's acceptance predicate (P2, with the thing as `PRED_TARGET`), its capacity and `COMSIG_SLOT_PRE_INSERT`. Either pre signal can return `COMPONENT_SLOT_BLOCK` to refuse the move.
- **The commit** is a single `forceMove`.
- **Bookkeeping lives in `doMove()`.** Right after the `loc` write, and before `Exited()`/`Entered()`, it calls `note_exit()`/`note_enter()` on the ledgers of the old and new locations. Those calls fire `COMSIG_SLOT_REMOVED`/`COMSIG_SLOT_INSERTED` and the holder's `on_slot_changed()`. Legacy `forceMove`s into a holder are therefore still accounted for, and land in the default slot.
- **Atoms created inside a holder** (`new X(holder)`) are recorded by `InitAtom`. The ledger's `sync()` catches anything else; it costs one `length(contents)` comparison when nothing is missing.
- **Declaring slots.** A holder type overrides `slot_def_types()` and returns a list of `/datum/slot_def` paths. Each definition is a shared singleton with:
  - an id;
  - an exposure;
  - a capacity model: none, count, size class, mass, or custom units through `cost()`;
  - `capacity_for(holder)`, which gives the capacity per instance;
  - an `accepts` predicate, plus an optional `holder_constraint` (P3): a `CONSTRAINT_*` kind read from the holder, for holders whose acceptance varies by type ([rules.md §3.1](rules.md#31-as-built-p3));
  - a drop policy: spill, delete, or transfer.
  The ledger itself (`/datum/ledger`) is created the first time the holder is used, so a closet nobody touches has none.
- **Drop policies.** `/atom/movable/Destroy()` calls `ledger_apply_drop_policies()` before anything else.
  - Spill moves things to `drop_location()`.
  - Transfer moves things into the holder's container's default slot, and spills them if that fails.
  - Delete deletes them.
  - Anything with nowhere to go is deleted.
- **Entry ids** have the form `slot#serial`. The serial is per holder and never reused, so an id goes stale once its thing leaves or changes slot. The state serializer numbers a holder's children in ledger order (`state_children()`). The collapse refcount check counts the ledger's references as belonging to the container.
- **Aggregates.**
  - Covered: every registered measure that has an aggregator (currently mass, heat capacity, size class, melting and ignition points, and heat protection), plus the tag words.
  - Each insert and remove updates them through a `/datum/property_accumulator`.
  - A thing's contribution is its own value combined with its own ledger's totals, so nested holders roll up. A change inside propagates to each enclosing holder.
  - `verify()` compares everything against a recomputation from scratch.
  - Changes to a child's own properties are not pushed yet. That waits for the reactor (S track); until then, callers use `ledger.refresh(thing)`.
- **Migrated holders.**
  - Closets, crates and lockers (`/obj/structure/closet`): one interior slot with custom units (`storage_cost_of()`) and the spill policy. `open()`, `close()`, `ex_act`, `examine` and `LateInitialize` all go through the API.
  - Folders: one pages slot that accepts `TAG_PAPERWORK` and uses the delete policy.
- **Stock slots (C9)** (`stock.dm`, `code/datums/vending/stored_item.dm`):
  - Vending machines and smartfridges declare an `internals` slot (parts, circuit, coin; policy `SLOT_DROP_HOLDER`, left to the machine's Destroy until C6) and a custom-units `stock` slot.
  - Each product is a `/datum/stored_item` record: type path, latent `amount`, and deltas (price, category, variant, or a shared state blob). A real item is made only when one is taken out; cartridge restock adds to `amount`.
  - An inserted item whose state serializes, with no contents and nothing running, folds into the count when its `state_hash` matches the record's (vending: a pristine item's; smartfridge: the first one's). Anything else stays real in the stock slot and the record's `instances`.
  - Slot definitions gained `latent_used()` (counts towards capacity and `slot_used`) and `drop_latent()`, which the base Destroy calls before the real contents. Smartfridge stock spills (latent copies made real); vending stock is deleted with the machine, as before.
  - Material stacks don't serialize yet (`recipes` has no codec), so sheet storage keeps them real.
- **Lint.** `tools/ci/containment_lint.py` checks `tools/ci/containment_allowlist.txt`, which holds per-file counts of the legacy sites (681 in 310 files at C1). A file may not gain sites.

## 3. Slots

**A slot definition** is a shared `/datum/slot_def` that holder types declare. It holds:
- **Accepts:** a constraint ([rules.md §3](rules.md#3-constraints)).
- **Capacity model:** a count, a volume by size class, or a weight.
- **Exposure:** external or internal (§3.1).
- **Layer:** the slot's order among layers at the same place.
- **Zones covered**, for equipment.
- **Environment**, for internal slots: shared with the holder's surroundings, sealed with its own interior, or insulated with a conductance.
- **Interactions** it adds: insert, eject, open, close.
- **Drop policy:** what happens to contents when the holder is destroyed.
- **Visibility and UI hints.**

### 3.1 Exposure

| | External: held, worn outer layer, mounted, attached accessory | Internal: pocket, bag interior, closet, belly, machine internals, implant |
|---|---|---|
| Environment | The holder's surroundings | The holder's interior |
| Visibility | Rendered (overlays, in-hand sprites) and examinable | Hidden until opened |
| Damage | Hit first, and shields what's inside | Only what passes through |
| Reach | Direct interaction | Needs an "open" interaction |
| Latent | Never, since it's visible | Allowed |

**Layers** order slots at the same place: undersuit, uniform, suit, hardsuit. Each layer is internal relative to the one outside it.

### 3.2 Propagation paths

Heat, damage, pressure and radiation all walk the same path:
1. the environment;
2. external slots;
3. layers, from outermost inwards;
4. internal slots;
5. contents.

Each step on the path carries its couplings: thermal conductance, damage pass-through and armour, pressure sealing, radiation shielding. No type writes its own "does heat reach the pockets" code. In Rust, only containers that matter thermally get a heat node, and its coupling to the parent node comes from that step ([simulation.md §7](simulation.md#7-heat-m4)).

### 3.3 As built (C2)

The code is in `code/datums/containment/paths.dm`, with the heat coupling in `heat_adapter.dm`; defines are in `code/__defines/containment.dm`.

- **Exposure.** `SLOT_EXPOSURE_EXTERNAL`, `SLOT_EXPOSURE_INTERNAL` and `SLOT_EXPOSURE_SEALED`. Internal and sealed slots are inside the holder's shell, so the holder's insulation and armour cover them. A sealed slot has its own interior and blocks gas.
- **Slot data.** Each `/datum/slot_def` also carries:
  - `layer`: a `SLOT_LAYER_*` value, higher is further out; `SLOT_LAYER_NONE` means the slot is not layered;
  - `heat_transmission` and `radiation_transmission`: what crosses the slot's own boundary;
  - `damage_transmission`: the share of each `DAMAGE_*` kind that passes from a hit on the holder. Null takes the exposure's default from `dq_path_default_damage()`;
  - `reaches_mobs`: off by default, so living contents take no heat or damage along the path. They get heat from their environment (H2) and hits through occupant rules (C8).
- **Default damage shares.** They are conservative:
  - External slots get 0 for every kind; equipment zones decide (C3, D2).
  - Internal slots let through 0.5 of pierce and 0.25 of corrosive. Sealed slots let through 0.5 of pierce and no corrosive.
  - Thermal and cold go by the heat path, and radiation by its own path.
  - Ionic and blast get 0, because `emp_act` recursion and D5's `explosion_contents_severity()` already reach contents.
- **One step,** `dq_path_step(holder, child, effect, kind, penetration)`, multiplies three factors:
  1. the slot's own transmission;
  2. for internal and sealed slots, the holder's attenuation: `1 - PROP_INSULATION` for heat, or `1 - armour` for damage (the kind's armour key, after penetration) and for radiation (`"rad"`);
  3. the same attenuation from every thing in the holder's layers further out, outermost first.

  Gas crosses a step unless the slot is sealed. `dq_path_share(child, from, ...)` multiplies the steps down a nested chain. A holder without slots passes nothing.
- **Damage.** `/atom/receive_damage()` ends with `propagate_damage(packet)`, and each child gets a packet of its own through its own `receive_damage()`, so nested holders pass it on in turn. Point kinds (blunt, sharp, pierce) land on one thing per slot; the other kinds reach every thing. A holder destroyed by the hit has already spilled its contents, so they get nothing.
- **Heat.** `/obj/fire_act()` calls `propagate_fire()` first. Each child is exposed at `ambient + (T - ambient) × share`, where the ambient temperature comes from `dq_heat_path_ambient()`. When M4 lands, `heat_coupling()`, `create_heat_body()` and `heat_recouple()` should pass the body's conductance through `heat_path_conductance()`, and `dq_heat_path_ambient()` becomes `get_interior_temperature()`. Latent entries get no bodies.
- **Insulation** is `PROP_INSULATION`, a P1 property on a ratio scale, read from the `/obj/var/insulation` type var.
- **Declared holders:**

  | Holder | Slot exposure | Insulation | Damage that passes |
  |---|---|---|---|
  | Closets, crates, lockers | internal (they share the room's air) | 0.5 | pierce 0.25, corrosive 0.25 |
  | Folders | internal | 0.1 | sharp 0.5, pierce 1, corrosive 0.5 |

- **Tests** are in `dq_containment_path_tests.dm`:
  - a closet and a freezer in a fire protect their contents per their insulation;
  - the path through a closet and then a folder;
  - weapon hits on a bag: blunt and cutting blows stay on the bag, a stab goes through, and armour and penetration change how much;
  - a closet, and a bag inside it, reached through the real `receive_weapon_hit()`;
  - a sealed slot blocks gas, including when nested;
  - three worn layers attenuate heat and blows in order.

**What later items need**
- **C3 (equipment).**
  - Declare body-part equipment slots with `layer` (`SLOT_LAYER_UNDERSUIT` .. `SLOT_LAYER_PLATE`) and external exposure. Pockets and the inside of a suit storage are internal.
  - Clothing sets `insulation` from its heat-protection data. `worn_factors` and zone armour then read the path instead of scanning.
  - Route mob hits to the covering layers through `dq_path_step`, with zones (`zones covered` in §3 is not built yet).
  - Decide `reaches_mobs` for anything that holds a mob.
- **C4 (storage).** `/obj/item/storage` gets an internal slot, and bags then take the default shares. Until then a bag passes nothing.
- **C5 (latent).** A damage share that reaches a slot holding entries resolves them, with one roll per group (§4.2). Heat stays on the container's body.
- **C6 (machine internals).** Internals are internal slots. Circuit boards and parts expressed as tiers take shares only once they are materialized.
- **C7 (vore).** A belly is a sealed slot with `reaches_mobs = TRUE` and its own damage and heat rules, replacing digestion's direct damage.
- **C8 (occupants and mechs).** Occupant slots set `reaches_mobs` and their shares, such as a pod's glass. D5's `explosion_contents_severity()` overrides become blast shares on those slots.
- **D2** interns armour. `dq_path_armor()` is the single read to switch over.
- **H2 and M4** wire in `heat_path_conductance()` as described above.

## 4. Latent contents

### 4.1 Three stages

| Stage | Held as | Moves on when |
|---|---|---|
| **Declared** | A generator: a spawn table, plus a seed if contents must be reproducible (state.md §9). Nothing is rolled yet. | Something needs exact facts about the contents |
| **Resolved** | Entries: type, count and delta, using the Variants spawn format (`list(count, "variant")`) | Something needs a real object |
| **Materialized** | Real atoms | Only back to resolved, by collapsing (§4.5) |

**Rolls happen only when needed.** A container resolves its generators when:
- a query needs exact facts: weight, "contains X", a scanner, a capability registry, an admin view;
- or the container's own simulation state first departs from default: its heat node activates, or damage passes through.

A closet at ambient temperature that nobody touches never rolls.

### 4.2 How a container stands in for its contents

- **Heat.**
  - The container's heat node includes the entries' heat capacity (per-type heat capacity × count).
  - It carries one `ThresholdSet` holding each entry group's thresholds. Crossing one fires a rule for that group: a data transform, or materialize and call the behaviour.
  - Entries have no heat nodes of their own.
- **Damage.**
  - The container's damage model decides how much passes through.
  - Each entry group is resolved from its type's integrity and resistances, with one binomial roll per group of identical items. Destroyed items are removed (with debris entries if needed); damaged items split off with an integrity delta.
  - Types marked "materialize on damage" become real and run their own proc.
- **Time.** Rot, discharge and slow reactions are caught up when an entry is materialized or queried. Timers exist only where something must happen at a specific moment.
- **Queries.** Weight, size, counts, value, contraband checks and flag checks are answered from type properties × count plus deltas, without creating anything.
- **Signals.** Type-level listeners materialize an entry when an event it listens for reaches its container ([state.md §8](state.md#8-signals)).

### 4.3 When to materialize

Materialize only what's needed, at these points:
- a closet is opened (its contents land on the turf);
- a storage UI is opened (§8);
- a specific item is taken, clicked or examined;
- an event whose rule is a behaviour;
- deconstruction;
- admin view-variables.

A materialized item is its type plus its delta, and its implied state is taken from the container.

### 4.4 Eligibility

Only **latent-safe** types can be latent:
- their `Initialize()` has no global side effects ([state.md §6](state.md#6-lifecycle));
- their state serializes.

Living things and anything that processes are never latent. PDAs, tracking implants, signalers, cameras and IDs become eligible once L2 and L3 move their registrations into `on_materialize()`.

**Legacy code.** It walks `contents` directly (about 590 loops, plus `GetAllContents`), and BYOND can't intercept that. So latent contents are enabled per holder type, only after that holder's code paths use the slot API. A lint flags raw `contents` walks on latent-enabled holders.

### 4.5 Collapsing back into entries

Collapsing is opt-in, for simple items that are created and discarded in large numbers and whose identity doesn't matter: casings back into a magazine, pills back into a bottle, blank paper. An item collapses only when it serializes (so it holds no relationships or running behaviour) and it has no contents. BYOND tends to reuse freed memory rather than return it, so avoiding the startup peak matters more than collapsing later.

### 4.6 Rollout

Rolled out in this order, measuring boot_memory's census at each step:

| Step | Holders | Estimated saving |
|---|---|---|
| 1 | Closets, crates, lockers | ~10k+ atoms |
| 2 | Mapped storage (691 mapped, ~4.4k direct items, ~800 nested storages) | ~5k+ atoms |
| 3 | Lights: bulb and emergency cell state kept on the fixture | ~2.6k objects |
| 4 | Ammo: round counts in magazines and guns; casings on ejection; projectiles created when fired | ~3k atoms from mapped magazines |
| 5 | Pills and pill bottles | ~46 containers per oxygen kit |
| 6 | PDAs, radios and headsets (after L2 and L3) | 14 app datums per PDA; encryption keys |

## 5. Machine internals (C6)

- **Parts become tier numbers**: `list(manipulator = 1, capacitor = 2)`. `RefreshParts()` reads the numbers, and real parts are created only on deconstruction or an RPED swap. That's about 3–6 parts on each of ~746 mapped machines.
- **The circuit board is its type path** until the machine is dismantled. That's about 2,300 boards, each with a `/datum/frame`.
- **Cells, wires and radio connections** are created on first use. Wires become a bitmask plus per-type definitions ([interactions.md §11](interactions.md#11-wires)).
- The 93 `in component_parts` checks and the sleeper's partial eject go away.

## 6. Equipment

**Where slots live**
- Equipment slots belong to body parts from the body rewrite's body plans: hands on arms, headwear on the head, and so on.
- Each slot has zones covered and a layer.
- Species gating becomes a constraint on the item type (body plan and fit), not `hud.equip_slots` plus `species_restricted` lists.

**Inventory actions**
- Equipping, unequipping, picking up, dropping and throwing are all ledger moves ([interactions.md](interactions.md)).
- `equipped()` and `dropped()` become slot signals.
- Items held in an external slot are always real. Their own internal slots (pockets, backpacks) can be latent.

**Per-zone aggregates, updated on equip**

| Aggregate | How it combines |
|---|---|
| Armour | Composed through the layers ([damage.md §4](damage.md#4-mitigation)) |
| Insulation | Thermal resistances added in series, which is the physically correct model |
| Pressure protection | From the sealed layers |
| Slowdown | Sum |
| Vision and hearing modifiers | Flags |
| Body factors from equipment | Declared by items, read by the body model ("Equipment: modifiers declare factors", `doc/health_system_review.md` §5.11) |

Today `get_heat_protection_flags` scans six slots every `Life()`, and `getarmor_organ` adds up clothing on every hit. Aggregates replace both.

**Deleted:**
- the per-slot typed vars;
- `u_equip`'s if/else chain;
- `get_inventory_slot`'s 22-case switch;
- `equip_to_slot`'s direct `loc` writes;
- the robots' raw `contents` edits.

The robots' `module_state_1..3` become slots on the module holder.

## 7. Pickup, drop, throw

These are interactions that perform ledger moves, so each one is a single atomic step. The 314 `put_in_hands` and 408 `drop_from_inventory` call sites become thin wrappers over the ledger, and then direct calls. On failure, an item stays where it was, instead of `put_in_hands` dropping it on the floor.

## 8. Storage (C4)

- A storage item is a holder with one internal slot, whose capacity model is by count, volume or weight.
- Insertion and removal are ledger moves; the `usr`-dependent paths and `can_be_inserted`'s recount are deleted.
- **Screen objects** are created for whoever opens the storage and pooled per viewer, instead of 2–4 per storage at init.
- **The UI can show latent entries** using each type's appearance, materializing an item only when it is clicked or dragged.

## 9. Vore (C7)

- **A belly stays an atom**, because a prey mob needs an atom as its `loc`. It becomes an **internal, sealed slot** on the predator.
- **Environment.** Its interior heat node is coupled to the predator's body heat node and air.
- **Modes become rules and rate models.**
  - Digestion is a damage stream into `injure()` at a rate. It already uses `INJURY_DIGESTION`, `INJURY_CORROSIVE`, …
  - Absorb, drain and heal are rate models.
  - Empty bellies cost nothing, and SSbellies is deleted.
- **Items** are digested through the damage pipeline's integrity instead of per-tick `digest_act`.
- **Consent preferences** (devourable, digestable, …) become interaction requirements.
- **Message lists** are shared per preset and copied only when customized.
- **Serialization.** The belly serializer becomes a client of the generic serializer.
- **What stays in the vore module:** the vore UI, messages and preferences.

## 10. Occupants and mechs (C8, with the body rewrite)

- **Occupant slots** are internal and sealed, and they define the occupant's environment (breathing and temperature).
  - Sleepers, scanners, cryo, cryopods, the DNA modifier, recharge stations, VR pods, resleevers, the implant chair and the gibber all use them.
  - Their occupant behaviour belongs to the body rewrite, so this lands after its phases.
- **Mechs**:
  - The pilot sits in a sealed occupant slot.
  - Equipment goes on external hardpoint slots.
  - Cargo goes in an internal slot.
  - Damage goes through the body model once the body rewrite adds a body host interface ([damage.md §5](damage.md#5-where-damage-lands)).

## 11. Other holders

- **Vending and smartfridge (C9).** Stock slots hold virtual counts per product, and only one item is materialized per vend.
- **Circuits.** Assemblies hold components in slots. Circuit types come from type properties rather than instances. Pins are created lazily, with values kept in a compact list.
- **Reagents.** Holders sit behind the same insert, remove and transfer API as a fluid store. Reagent datums become shared singletons plus an id → volume list, with `data` only where needed. Organ holders are created on first reagent (with the body rewrite).

## 12. Movement hot spots

- `doMove` no longer calls `Crossed`/`Uncrossed` on the contents of containers; only turfs cross.
- `onTransitZ` no longer recurses. Latent entries have no z-dependent state, and real contents that care subscribe.
- Recursive content walks go through the slot index instead: they drop from quadratic to linear, `recursive_content_check` on every `say` is replaced by hearing registration, and the depth-5 EMP recursion becomes a propagation path.

## 13. Tests and lint

**Tests**
- A random-operation test for every holder type: moves, destroys, merges and materializations, checking that nothing is lost or duplicated.
- Parity for every latent-safe type ([state.md §5](state.md#5-one-serializer-many-uses)).
- Heat and damage propagation path tests.

**Lint**
- No raw `loc =`, `contents +=` or `contents -=` on movables (C1).
- No raw `contents` walks on latent-enabled holders (C5).
- No `can_hold`, `allowed` or `species_restricted` lists (P3).
