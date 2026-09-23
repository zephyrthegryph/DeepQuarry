# State, lifecycle and registries (track L)

This document defines four things:
- what counts as an object's state;
- how state is written out and read back;
- what happens when an object comes into or leaves the world;
- how shared lists of objects are kept.

Latent contents ([containment.md](containment.md)), persistence, admin tools and parity tests are all built on it.

## 1. Kinds of state

| Kind | Examples | How it's handled |
|---|---|---|
| **Value** | Integrity, charge, uses left, labels, fingerprints, reagent volumes, variant, cooked | Saved. The **delta** is the value state that differs from the type's defaults. |
| **Derived** | Icon and overlays, a name built from state, cached totals, appearances | Not saved. It must be `tmp`, and it is recomputed on materialize. |
| **Implied by the container** | Temperature equal to the container's interior, pressure | Not saved. It is taken from the container when the object is materialized. |
| **Evolving with a closed form** | Rot, cell self-discharge, slow reactions, cooldowns | Saved as a value, a rate and a start time, and caught up when read |
| **Relationships and running behaviour** | References to other objects, timers, per-instance signal registrations, processing, registrations, anything alive | **Can't be serialized.** An object holding any of these stays real. |

The last row is the safety mechanism. Collapsing an object into data is just serializing it; if the serializer meets a relationship or running behaviour, it fails and the object stays real. No gameplay code decides eligibility, so there is no "if" to forget.

`/datum/proc/state_collapse_blockers()` (`code/datums/state/collapse.dm`) returns every reason an object can't collapse: references the codecs refuse, timers, processing, signal registrations with anything outside the subtree (type elements don't count), and extra incoming references. Serializing for persistence refuses only the references, since a running object, such as a processing belly, still has saveable state.

**Incoming references.** The checks above cover what an object holds, not who holds it. Collapse also requires BYOND's `refcount(obj)` to equal the references its container and contents account for. Any extra reference means another object or list points at it, so it stays real. Test builds run the reference finder on refusals to name the holder, which then becomes a registry entry, a codec or a `tmp` var.

## 2. Schema

BYOND already separates saved from unsaved vars: `issaved()` is false for `tmp`, `const` and `global` vars. So the schema of a type is its saved vars.

The API is `code/datums/state/schema.dm`. Built-in vars are skipped except a fixed appearance set (`STATE_BUILTIN_SAVED`: name, desc, icon, icon_state, dir, color, pixel offsets, …).

- **Hygiene pass.** Caches, references and runtime handles become `tmp`.
- **Reference lint (CI).** A typed var declaration that holds an object (`var/datum/…`, `var/obj/…`, `var/mob/…`, `var/list` of datums) must be `tmp` or have a codec. `tools/ci/state_schema_lint.py` parses the declarations and checks every saved var of each latent-safe type and its ancestors. Relationships that should keep an object real are listed, with a reason, in `tools/ci/state_ref_allowlist.txt`. It is what stops a new var from quietly breaking serialization.
- **Latent-safe types** set `latent_safe = TRUE` (`code/datums/state/latent_safe_types.dm`), and subtypes inherit it.
- **Components** that hold per-instance state serialize through the same codecs, as the component type plus its state. A component declares `state_mode`: saved, derived (dropped and rebuilt), or refused (the default). The sparse-var components (`code/datums/components/sparse_vars/`: forensics, alt appearance, …) come first.

## 3. Codecs

| Value | Encoding |
|---|---|
| Number, text, null | As is |
| Path | `{"#path": "/type"}` |
| Flat list, assoc list | Element by element, recursively; lists with non-text keys as `{"#pairs": [[k, v], …]}` |
| Reference to a child entry in the same subtree | A stable child ID: `{"#child": "2.1"}`, the contents index path |
| Reference to a registered singleton (material, reagent, decl, species) | Its registry ID: `{"#reg": [kind, id]}` |
| File resource | `{"#rsc": "icons/…"}` |
| Any other reference | **Refused.** Serialization fails and the object stays real. |

A var can name a codec in its type's `state_codecs()`: `child`, `owned` (a datum only this object refers to, saved as its own nested state), `reagents` (the holder's capacity and reagents) and `atom_flags` (flags without runtime bits) exist today.

## 4. Deltas

- A **delta** is the saved vars whose values differ from the type's defaults plus its variant (the `code/datums/variants/` tables).
  - Scalars compare with `initial()`. Applying a delta also resets every other saved scalar to `initial()`, so randomness in `Initialize()` can't leak into a materialized copy.
  - `initial()` is null for list vars. In a latent-safe subtree, lists compare with a pristine instance, made once per type; `state_type_list_default()` exposes those defaults (the property registry reads per-type `matter` through it). Other types save every list var that is set, as the vore serializer did.
- The **canonical form** sorts keys and normalizes numbers, and its hash identifies identical items. The ledger merges and splits entries by that hash ([containment.md §4](containment.md#4-latent-contents)).
- **Versioning.** Each type has an integer `state_version`. Bumping it comes with a `state_migrate()` step that upgrades older deltas, and `GLOB.state_type_migrations` maps renamed or removed types. Pre-L1 flat blobs load as version 0.

## 5. One serializer, many uses

- latent entries ([containment.md](containment.md));
- persistence between rounds;
- admin save, load and duplicate;
- map templates carrying object state;
- replays and bug reports;
- **parity tests**: for every latent-safe type, `materialize(serialize(x))` must equal `x` for sampled states.

**Existing pieces to fold in:**
- `/datum/belly_serializer` is gone (L1). Bellies and soulgems save through the generic serializer, and older saved bellies still load.
- `json_savefile` stays as a storage format.
- `/datum/proc/serialize_list` is gone (L1): the logger now writes a datum as its saved state.

## 6. Lifecycle

`Initialize()` today mixes two jobs: setting up the object's own state, and registering it with the world. A latent object must do the first without the second.

- **`Initialize()`** sets only the object's own state and declares its slots and generators. It does not create sub-objects. It does not add itself to global lists, register global signals, join radio networks or start processing.
- **`on_materialize()`** runs when the object enters the world as a real atom. This covers creation in the world, spawning from a latent entry, and map load. It registers with registries, attaches type elements and starts watches.
- **`on_dematerialize()`** is its exact inverse. It runs before the object collapses into an entry or is deleted.
- **Sandbox test.** Every latent-safe type is created in a sandbox, and the global lists and registries are compared before and after `Initialize()`. They must be unchanged.

## 7. Registries

Ad-hoc global lists (radios, PDAs and the messenger, trackers, cameras, machine lists, …) become **registries**:
- **Typed and weak.** They hold registry IDs, not strong references, so they can't cause hard deletes.
- **Membership follows the lifecycle.** An object joins in `on_materialize()` and leaves in `on_dematerialize()`. No one adds or removes by hand.
- **Capability queries** can include latent entries. A type that declares a capability ("contains a tracking beacon", "has a radio") shows up in its container's aggregate. A query returns the holder and the entry, and materializes the entry if the caller needs the object.
- **Hard deletes.** Registries remove a common cause of them: a global list still holding a deleted object. The profiled round had 428, at about 140 ms each.

**As built (L3).** `code/__defines/registries.dm` has the API; `code/datums/registries.dm` the datum.
- A registry is a `/datum/registry` singleton per id (`REGISTRY_PDAS`, `REGISTRY_MACHINES`, �), declared in `code/datums/registry_declarations.dm`. It has `add`, `remove`, `members`, `count`, and optional keyed filing (`keyed = TRUE`, `registry_key()`, `rekey()`, `REGISTRY_KEYED(id, key)`).
- A type declares membership with `REGISTRY_MEMBERSHIP(/type, REGISTRY_X)` next to its definition; subtypes inherit it. The declared set is cached per type. `/atom/on_materialize()` joins and `/atom/on_dematerialize()` leaves; nothing else writes a registry. `skips_registry(id)` is a rare per-instance opt-out fixed at Initialize() (energy-ball miniballs).
- Readers use `REGISTRY_MEMBERS(id)`: the registry's own list in join order (cameras keep their name-sorted order after the first sort). Copy before deleting members while iterating.
- Members are strong references, not IDs. Removal is guaranteed instead: `Destroy()` always dematerializes. `dq_registry_no_deleted_members` checks no registry holds a deleted object.
- A member is still registered while its own `Destroy()` body runs (it leaves in `/atom/Destroy()`), so a Destroy() that scans its own registry must skip `src`.
- `tools/ci/registry_lint.py` refuses new self-adding global lists; `tools/ci/registry_allowlist.txt` lists what is left and why (mob lists, state-driven lists, datum lists).
- Radios, PDAs, GPS units, tracking implants and ID cards (including guest passes) now register only in `on_materialize()`, and the sandbox test and lifecycle lint cover them (`dq_lifecycle_clean_types`). None is marked latent-safe yet: their state has not been through the serializer round trip. Cameras register in `on_materialize()` too, but `/obj/machinery` still starts processing in `Initialize()`.

## 8. Signals

| Signal use | Example | Can the object be latent? |
|---|---|---|
| Behaviour every instance of a type has | An element listening for equip or EMP | **Yes.** It is type data with a listen mask. When such an event reaches a container holding a latent entry of that type, the ledger materializes the entry and delivers the event. |
| Component with per-instance state | Forensics, a charge component | **Yes**, through codecs |
| Relationship between two instances | A tracker registered on one mob, a signaler paired with a door | **No.** It is a live reference, so the object stays real. |
| Global listener | Listening to a global signal | **No**, unless the type declares a capability that a registry routes |

**L4 fixes:**
- **Type elements.** Behaviour that every instance of a type has is declared as elements on the type, attached in `on_materialize()`. There is no per-instance datum, and the listen mask is known for latent routing.
- **Declared signals.** Each signal is declared with its argument count, and debug builds assert it. A `SEND_SIGNAL` with the wrong arguments is silent today.
- **CI audit.** Every `COMSIG_*` must be sent somewhere and listened to somewhere. Today some are defined but never sent: the storage signals, the four machinery signals and the screentip signals. `COMSIG_TURF_CHANGE` is listened for but never sent. Each gets wired up or deleted.
- **Pooled dispatch.** Sending to several listeners uses a pooled buffer instead of allocating `queued_calls` every time.
- **Simulation dependencies** go through the reactor, not signals ([reactor.md §8](reactor.md#8-signals-or-the-reactor)).

## 9. Randomness

BYOND has one global random generator.
- Rolling later (latent generators) just draws different numbers, and gameplay doesn't care.
- For reproducible content (tests, replays, "same seed, same station"), a generator keeps a seed and rolls from a Rust RNG stream (`core::rng`).
- Never reseed BYOND's global generator, because everything else shares it.

## 10. Lint rules

| Rule | On after |
|---|---|
| Vars that hold references are `tmp` or have a codec | L1 |
| No global list writes, global signal registration, radio joins or processing starts in `Initialize()` of latent-safe types | L2 |
| No new ad-hoc global lists of instances; use a registry | L3 |
| Every signal declared with its argument count, and sent and listened for | L4 |
