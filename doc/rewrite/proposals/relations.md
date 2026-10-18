# Proposal: finishing the relations layer and the stored-reference migration (design only)

Status: decisions D1 to D21 approved by the user (2026-10-17), with three final calls written in below (D6 hot paths, D11 native built-ins, D17 `SPILL_FRACTION`); this document is the written form. Docs only: no code, and `final_api.html`
is not edited (section 11 lists the edits it needs).
Scope: doc section 6 (`final_api.html`: "Relations", "Storing references", "Naming an entity in data"), `proposals/reference_storage.md`,
`lifecycle.md`, `containment.md` section 4, and the 691 sites in `tools/ci/stored_refs_baseline.txt`.

Verification: every claim below was read against the tree at `origin/master` 1c1d649c08 (the worktree merged it). A citation is `file:line` on that
tree. **(unverified)** marks a claim not checked against code (a design statement, or a count that needs the `analyze` report). Counts made with `grep`
say so; they are approximate, never the lint's numbers.

## 0. Summary

1. **The relation layer is built; what is missing is discipline at its edges.** `ref_one/ref_many/owns_one/owns_many/links()/slot()` and the `rel_*`
   verbs are on master (`code/engine/declare/entries.dm`, `relations.dm`). What lets references leak today is: a write to an undeclared var is silently
   accepted (D1), handles are hand-stored in vars (D5), reflective writes bypass the verbs (D14), BYOND's built-in reference storage has no declared path (D11, D15),
   and the lint is blind to untyped vars, assoc keys and text keys (D8, D9, D12).
2. **Two storage kinds stay** (relation, weak ref), but the weak ref becomes a *relation option* (`weak = TRUE`) instead of a hand-written handle in a var. A
   token (a plain value) remains only in data that is saved, pinned or sent to a UI (D5).
3. **One naming scheme in content** (`entity_handle`, later `ref_token`); `own_key`, `adj_handle` and `vg_entity` are engine-only; a stored `REF()` or
   `locate()` text is banned (D9).
4. **Destroy policy is stated once** (D17): `SPILL` is the default for anything that sits in a slot; `SPILL_FRACTION(f)` (default 25%) spills a share and deletes
   the rest (vending stock uses it); `DELETE` only for the holder's own construction; anything with a mind or client (and the nuke disk) survives a container's
   deletion whatever the policy.
5. **Latent contents** (D19): a declared relation pins an atom real; only weak refs survive a collapse.
6. **Closure** (section 4): every path a reference can be stored by ends in a declaration, a lint or a count.

Crosswalk of the user's approved items to decisions: 1 to D1; 2 to D5; 3 to D3; 4 to D6; 5 to D9; 6 to D10; 7 to D8; 8 to D11; 9 to D12; 10 to D13;
11 to D14; 12 to D7; 13 to D15; 14 to D16; 15 to D17; 16 to D18; 17 to D19; 18 to D20. The first draft's D1 to D8 are kept where valid: D1 to D2, D2 to D3,
D3 to D4, D4 to D5, D5 to D7, D6 to D8, D7 to D10, D8 to D21.

## 1. What master has today (verified)

| Fact | Where |
|---|---|
| `ref_one/ref_many(var, type, on_other_deleted, on_unlink, by, key, target_key)`; `owns_one/owns_many(..., on_destroy = ON_DESTROY_DELETE default, copy_on_write, starts...)`; `links(a_end, b_end, hot, a_many, b_many, ..., sparse, holds_while, ..., conflict = REPLACE)`; `slot(id, accepts, capacity, exposure, at, on_destroy, starts)` | `code/engine/declare/entries.dm:73-200` |
| The legacy `ownership()` and `relations()` table procs, `own_set/own_add/own_put`, `om_link` are hard-banned | `tools/ci/lint_scopes.toml:1090-1095,1355`, and the `banned` list at 724 |
| An undeclared `rel_set` / `rel_add` does not fail: `own_entry_of_kind()` records an implicit `OWNK_REL` entry `list(OWNK_REL, RELS_PLAIN, null, null, is_list, null, CLEAR, ...)` with no report (an undeclared *owned* var is reported) | `code/engine/refs/table.dm:434-451` (the learn branch is 439-443) |
| `rel_view_set` on a var with no entry writes it raw; its comment ("undeclared view, reported above") is stale: nothing was reported | `code/engine/refs/views.dm:177-188` |
| A second owner is refused with `OWN_REPORT`: `own_stamp()` reports "already owned by ..., needs own_transfer()" and returns FALSE | `code/engine/refs/ownership.dm:116-127`; `OWN_REPORT` is `dq_lifecycle_report` (a once-per-message `stack_trace`, `lifecycle_links.dm:37-46`), a runtime that fails a test run |
| Deleting an owned value from elsewhere clears the owner's var (`own_release_from_owner`), with no report | `ownership.dm:540-555` |
| `owner_of(D)` is a text `locate()` plus a membership check, not a stored reference | `ownership.dm:74-80` |
| Handles: `entity_handle(D)` ("id:gen"), `resolve_handle(h)`, `entity_handle_park/unpark` | `code/engine/time/handles.dm:49,171,134` |
| A client handle is `"@ckey"` and resolves through `GLOB.directory`, so a reconnect resolves to the *new* client | `handles.dm:55-58, 202-203` |
| A turf handle carries `#<generation>` once its z-level was released and reused; a plain turf handle resolves null after a release | `handles.dm:52-54, 205-231` |
| Pooled types: `/datum/act`, `/datum/seq_frame`'s state, operation context, damage packet; an unforced `qdel` of a pooled record is refused | `code/contracts/acts/context.dm:22`, `code/engine/kernel/sequence_state.dm:64`, `code/engine/parts/operation_context.dm:3`, `code/engine/refs/damage_packet.dm:16`; `code/engine/state/pool.dm:60-80` |
| `slot()` drop policy defaults to SPILL; only `on_destroy = ON_DESTROY_DELETE` is read from the entry (other values are ignored) | `code/engine/refs/containment/slot_def.dm:50,172-190,290` |
| `SLOT_DROP_DELETE` runs `spent(thing)` with no check of what the thing is | `code/engine/refs/containment/lifecycle.dm:111-113` |
| `is_mind_slot` / phase 0.5 is a no-op: no slot sets it outside one test | `lifecycle.dm:14-16`; `code/modules/unit_tests/dq_destroy_transaction_tests.dm:191` |
| Collapse into a latent entry treats relation views naming the node as accounted for ("collapse parks them and they re-link") | `code/engine/state/collapse.dm:144-150`; `rel_go_dormant` / `rel_wake` at `views.dm:588,605` |
| `stored_refs` treats `/turf /area /client /image /mutable_appearance /list ...` as non-references; an untyped var (`declared` empty) is not a reference | `tools/analyze/src/lints/stored_refs.rs:74, 91-93` |
| Baseline: 691 sites, var 523, list 168 | `tools/ci/stored_refs_baseline.txt` |

Counts (grep, approximate, non-test): `owns_one/owns_many(` 1606 lines, `ref_one/ref_many(` 1365, `links(` 72 (line-initial), `slot(` 18, `rel_set|rel_add` 5402.

## 2. The final relation kinds

| Kind | Declared as | Meaning | Other end dies | Holder dies |
|---|---|---|---|---|
| Owned | `owns_one` / `owns_many` (no location) | holder owns a datum that has no place in space | var cleared, with a debug report if it was not the holder's own disposal (D20) | value disposed by `on_destroy` (DELETE default, SPILL, PRIVATE_COPY) |
| Slotted | `slot()` | something that sits inside the holder in space | removed from the slot | slot policy: SPILL default; `SPILL_FRACTION(f)`; DELETE only for the holder's own construction; `survives_container` things always spill (D17) |
| Reference | `ref_one` / `ref_many` | holder names it, does not own it; reverse-indexed, published | `CLEAR` (default) or `DELETE_ME`; `on_unlink` runs | view cleared |
| Weak reference | `ref_one/ref_many(..., weak = TRUE)` (new) | a generation-checked handle stored; accessor generated; no reverse index, nothing published | the accessor reads null; nothing runs | nothing to clear |
| Pair | `links(A::a, B::b)` | both ends name each other; one write maintains both | other end clears (`conflict = REFUSE` or `REPLACE`) | both clear |
| Sparse pair | `links(LINK_END(...), ..., sparse = TRUE)` | ends live in engine records (buckle, pull, grab, orbit) | both clear | both clear |
| Keyed | `ref_*(by = nameof(id))` | points at the live target whose id var matches | re-links on id write / materialize | view cleared |
| Native (new) | the existing kinds (`ref_one`, `ref_many`, `links`, `slot`) declared by the engine on the base types over BYOND's built-in vars and lists, with native storage (D11) | what a built-in holds: `vis_contents`/`vis_locs`, `client.screen`, `client.images`, `image.loc`, `client.eye`/`perspective`, `mob.client`/`key`, `atom.particles` | removed from the built-in list or var by generated teardown | its entries removed |
| Membership | `membership()` / `registry()` | engine-owned store of live members | member leaves | leaves on dematerialize |
| Token | `entity_handle` / later `ref_token` in **data** only | a plain value in saves, pins, UI payloads | resolves null | n/a |

Engine-internal (never written by content): grants, listeners, members, timers, contained items, `own_key`, `adj_handle`, `vg_entity` (D9).

## 3. Decisions

### D1. Declare what is written (Wave 0)
Problem: `rel_set` on an undeclared var builds an `OTHER_CLEAR` entry with no report (`table.dm:437-451`, `views.dm:177-188`), so about 200 baseline vars are already
written through `rel_set` and behave as `ref_one` without saying so. By-name overlap of baseline var names with `nameof(...)` arguments of
`rel_set/add/remove/clear/take/move`: 278 of 523 var sites, 186 distinct names (an upper bound: a name shared by two types over-counts; the exact number needs
the `analyze` report) **(count approximate)**. The one example checked: `nttransfer::remote` is written by `rel_set` (`code/modules/modular_computers/file_system/programs/generic/nttransfer.dm:137`) and is in the baseline.
- (a) Declare every such var (mostly `ref_one`), then make an undeclared write an error.
- (b) Leave learning in place.

**Recommend (a).** Order: declarations first (about 190 to 278 one-line `ref_one`), then `own_entry_of_kind()` stops learning: an undeclared relation write is
`OWN_REPORT` (a test failure) and the lint `rel_write_undeclared` (static: a `rel_*` call whose `nameof` names a var no relation declares) is a hard ban with an empty baseline.
Tests that raw-set fixtures keep `TEST_RAW_SET`. This also removes the learned entries as a source of tables that differ by call order.

### D2. Default behaviour when the other end is deleted (was D1)
**Recommend:** `ref_one` with `OTHER_CLEAR`; `DELETE_ME` only where the holder is meaningless without the target (reviewed per wave); `owns_one` when the holder
creates the value and nothing else keeps it; `on_unlink` where the old `Destroy()` did work.

### D3. Pairs, cardinality, conflict (was D2, plus the approved `conflict` item)
- (a) A pair whose two vars both exist is `links(A::a, B::b)`; one write maintains both ends; replacing a single end unlinks the old partner on both sides.
- (b) One end only: `ref_one`, look the inverse up when needed.
- (c) Hand-kept inverse vars: rejected (the leak source).

**Recommend (a)/(b)** as before, with two engine changes:
1. `conflict = REFUSE` becomes legal on a **var-pair** link. Today `entry_link()` reports "holds_while, contributes and conflict are for a sparse pair; a pair of vars always replaces" (`entries.dm:161-162`), and only the sparse `link_make()` honours REFUSE (`code/engine/declare/link_state.dm:147-150`). The var-pair write path (`rel_view_set`, `views.dm:177-205`) must refuse when the far end already has a partner. A refusal returns null and reports like a refused typed write.
2. `links()` with an **owns_* end** is *not supported today*: `link_patch_table()` skips an end whose var already has an entry (`code/engine/declare/relations.dm:288`), so a var declared `owns_one` keeps its owns entry and the pair is silently not maintained at that end. Plan: the build rejects `links()` naming a var that another entry declares (error, not skip), and the supported form for "owner owns the part and the part names its owner" is D6 (`owner_of`), not a link. If a real site needs a pair with an owned end, it gets its own engine case, designed then **(unverified: no site found yet)**.

A `paired_vars` lint (two vars naming each other with no `links`) rejects new ones once wave 3 converts the old.

### D4. Keyed and sparse (was D3)
**Recommend:** `by = nameof(id_var)` for id-named targets (power network id, shuttle tag), `sparse = TRUE` for base-type pairs. First commit of wave 0 pins `by =` with a test
that it re-links on materialize, on id write and on target delete (the doc says so; the repo should prove it **(unverified: no such pin found)**).

### D5. Weak references are a relation option; tokens only in data (was D4, plus the approved `weak = TRUE`)
Today a weak ref is a hand-stored handle in a var (`var/x_handle = entity_handle(y)`, read with `resolve_handle`). That is a third storage kind written by hand, with
its own accessor per site, and it hides from the lint (a text var is not a reference).
- (a) `ref_one/ref_many(nameof(v), type, weak = TRUE)`: the build stores a generation-checked handle in the var, generates the accessor (`v()` returns the datum or null),
  and builds no reverse index and publishes nothing. Writes go through `rel_set/rel_add`. `on_unlink` and `on_other_deleted` are a build error with `weak` (nothing runs when the
  target dies); a reader that must react to the target's death uses a normal `ref_one`.
- (b) Keep hand-stored handles.

**Recommend (a).** Test per site (kept from the first draft): if the old code nulled the var on target death, or a stale-ref null check gated behaviour, it is a normal relation; if it only null-checks at use,
it is `weak = TRUE`. `nttransfer::remote` is a **relation**, not a handle: it is written by `rel_set` today and its holder expects the clear. Tokens (`ref_token`, `entity_handle` until the rename) stay only for **data**: saves, pins,
UI payloads, circuit pins, request fields. Resolve once per proc, never per tick per member (a repeat `entity_handle` costs about 1.6 us and `resolve_handle` 4 us, `reference_storage.md`).
A weak relation to a latent (collapsed) entity resolves null until it re-materializes (`entity_handle_park`, `handles.dm:134-143`, resolve at 178-181).

### D6. Owner back-references (approved item 4)
Examples from the baseline: `/datum/reagents::my_atom`, `/datum/disposal_system_connection::owner`, `/datum/request::owner`, `/obj/item/shield_projector/line/exosuit::my_mecha`.
- (a) When the holder **owns** the value (`owns_*` or `slot`), delete the back-reference var and read `owner_of(value)` (`ownership.dm:74`). The owner stamp (`own_holder_ref`, `own_slot`) already exists, so no storage is added and the var cannot go stale.
- (b) Otherwise, or on a **hot path**, `ref_one` (or `weak = TRUE` if only a null check is needed). `owner_of` parses text and calls `locate()` (cost not benchmarked **(unverified)**), so it is not for per-tick member loops.

**Decided (user, 2026-10-17): `ref_one` on hot paths, derived `owner_of` elsewhere** (a then b, as written). Each conversion states which it is. Existing `rel_set(R, nameof(R.my_atom), PB)`-style writes (`code/modules/mob/living/silicon/robot/robot_modules/station.dm:697`) become declarations or disappear.

### D7. Pooled records (was D5, plus approved item 12)
Pooled types (`/datum/pooled` subtypes: acts, sequence state, operation context, damage packet; `pool.dm:60-80`) are reset on release and **never `qdel`'d**, so a `ref_*` to one would never clear and would show the next taker's data.
- A pooled type may never be the **target** of a `ref_*`, `links()`, `owns_*` or `weak` relation (a build error). Anything that must outlive a trigger takes `A.snapshot()` or a token.
- A pooled record's own entity fields stay transient: kernel relations (weak while a pending op waits, strong from its reservation, final_api "Do is a commit") for `pending_op`, `request`; `act` fields are reset by the pool.
- **Structural reset check:** a test (and an analyze rule) per pooled type proves `release()` returns every field to its initial value (`snapshot()` of a released object equals a fresh one), so a new field cannot be forgotten. No path exemption: the exempt-by-type entry for `/datum/own_entry` style records is not copied to pooled types.
- NTSL is not exempted by path (D8): it owns its AST under the program.

### D8. Framework state and the classifier (was D6, plus approved item 7)
- Definition and compiled-table types (registries, `/datum/*_def`, flyweights, entries) are exempt by type in `[lint.stored_refs.lists] exempt_types` (`lint_scopes.toml:1441`), reviewed per type.
- Run-state holders (`request`, `pending_op`, `input_event`, live `activation`) are converted (D7).
- Interpreter (NTSL): `owns_one` the AST under the program if the program is deleted by an owner; else treat as one run's scratch **under a reviewed type**, not a path exemption.
- **The lint fails closed.** Today an untyped var is never a reference (`stored_refs.rs:91-93`), and a list's writes count only when the value's static type is known. The lint gains: (1) an `untyped` rule: a var or list with no declared type that any proc assigns a value the model types as an atom/datum, or whose type cannot be known and is assigned from a call, is reported (fail closed: unknown counts); (2) native built-in refs (D11); (3) assoc **keys** (D12). A new rule seeds its own baseline (`stored_refs_baseline.txt` is shrink-only and never takes new sites). The size of the new baselines is **(unverified)**; wave 0's `analyze` report sets them.
- `NOT_REFS` (`stored_refs.rs:74`) is revisited item by item: `/turf` and `/client` become handle-or-relation (D10); `/image` and `/mutable_appearance` are references when they carry `loc` (D11); `/area`, `/world`, `/savefile`, `/regex`, `/icon`, `/sound`, `/matrix` stay (never deleted or values).
- No `ALLOW(stored_refs)` in any case.

### D9. One naming scheme for an entity (approved item 5)
Today an entity is named by: `own_key` ("id:num:type", `ownership.dm:33-55`), `entity_handle` ("id:gen"), raw `REF()` text (508 `REF(` sites and 474 `\ref[` sites outside tests, about 70 of the `REF(` lines are hrefs; the rest is unclassified **(grep, approximate)**), `adj_handle` (`code/engine/lifeforms/adjacency.dm:40`, an index into the adjacency table), and `vg_entity` (a Rust entity id, `VG_ENTITY_INDEX_MASK`, `code/__defines/verdigris/_bindings.dm:574`).
- **Content uses only `entity_handle`** (later `ref_token`).
- `own_key` is internal to the relation engine; `adj_handle` and `vg_entity` are engine-only Rust handles, never in content.
- **Stored `REF()` / `locate(text)` is banned.** A REF text may be built and resolved inside one request (a Topic href `?src=[REF(src)]`). Lint `ref_text`: a `REF()` / `\ref[` result assigned to a var, list, assoc key or deferred argument is reported; ratchet on `\ref[`; a `locate()` whose argument is such a value is reported. Known stored-text sites to convert: `mob_chunk` watchers and `living_refs` (`code/modules/mob/mob_chunks.dm:18-23, 33-34`), pack `sightings` ("ref text of a mob", `code/modules/combat_ai/pack/pack.dm:33`), the `REF(host)` key in `SStgui.modals` (`code/controllers/subsystems/tgui.dm:745`), `contracts.dm:105`, and the engine's own staleness keys (`code/engine/change/staleness.dm`, `refresh.dm`: engine, exempt by path).

### D10. Turf and client vars become handles; saved handles are banned (was D7, plus approved item 6)
Today `/turf` and `/client` are not references to the lint, so any var of them is unchecked (about 145 turf-typed and 46 client-typed member lines, by a line-pattern count **(approximate)**; the baseline has 20 `@/client::` sites).
- A turf var is a `ref_one`-class declaration whose stored form is a handle. Turfs are not deleted, but their identity changes when a z-level is recycled: the generation is already on the handle (`handles.dm:52-54`), so a stale turf handle resolves null (`handles.dm:205-231`).
- A client var is a handle that **resolves null after disconnect and never to the reconnected client**. Today the handle is `"@ckey"` and `resolve_handle_keyed` reads `GLOB.directory[ckey]` (`handles.dm:55-58, 202-203`), so it *does* resolve to the reconnected client. Change: the client handle carries a connection generation (bumped on `Logout`/new connection); `resolve` compares it. A player-identity need that survives reconnect uses the ckey or the `persistent_client` record, not a client handle.
- **Saved handles are banned, client included.** Handles are per round and per connection. Lint `saved_handle`: an `entity_handle()` result (or a var declared `weak`) written to a saved var or a savefile writer. Saves store ids, ckeys or names; on load a relation re-links by `by =`.

### D11. BYOND built-ins that hold references are engine-declared relation ends (approved item 8, final form)
Decided by the user (2026-10-17): visual references are **not** a special case and there is **no new relation kind** (the earlier `visual(...)` / `vis_one` / `vis_many` sketch is dropped). Every BYOND built-in var or list that holds a reference
becomes a relation end declared **once, in the engine, on the base type**, using the existing kinds (`ref_one`, `ref_many`, `links`, `slot`) with **native storage** (the value stays in the built-in var or list; the build adds the reverse index, publishing and
teardown around it). Each end is declared with its inverse where BYOND has one, and its teardown is generated into the destroy transaction (phase 5, with `client.screen` release), so the holder or the held thing leaving always removes the entry.
Writes go only through `rel_*` verbs or an engine choke point; a raw `+=`, `-=`, `=` or `.Add()` on one of these built-ins outside the engine is a lint finding (`native_ref_write`, seeded baseline in its own commit, ratchet then hard ban).

Master today: a dying **movable's** own `vis_contents` is cleared and it is removed from its `vis_locs` holders (`code/game/atoms_movable.dm:140-143`); nothing declares the rest. The reference finder and leak check skip `vis_*`
(`code/modules/admin/view_variables/reference_tracking.dm:162-163`, `code/datums/lifecycle/leak_check.dm:40`), and `/image` is in `NOT_REFS`.

**Inventory** (grep counts approximate; every row is covered before the wave closes):

| Built-in | Holds | Relation form (engine-declared, native storage) | Inverse | Today |
|---|---|---|---|---|
| `loc`, `contents`, `locs` | containment | `slot()` / the containment layer (`containment.md`) | `loc` <-> `contents` | already containment; writes are `forceMove` / slot verbs |
| `vis_contents` | atoms shown through a holder | `ref_many` on `/atom` | `vis_locs` | 161 sites (grep); movable teardown only |
| `vis_locs` | holders showing this atom | the generated inverse of `vis_contents`, read-only | `vis_contents` | 10 sites (grep) |
| `client.screen` | objects on a client's screen | `ref_many` on `/client` | none | released in phase 5 for the client only |
| `client.images` | images shown to a client | `ref_many` on `/client` | none | 109 sites (grep) |
| `image.loc` (`image(loc =)`) | the atom an image rides on | `ref_one` on `/image` (an `/image` with a `loc` is a reference; the `NOT_REFS` entry is narrowed) | none | 18 sites (grep) |
| `client.eye`, `client.perspective` | the viewed atom | `ref_one` on `/client` | none | unchecked today |
| `mob.client` / `client.mob` / `mob.key` / `mob.ckey` | the native player link | one `links(/mob::client, /client::mob)` pair, written only by the `bind_player(mob, key)` choke point (D13) | the pair | about 104 raw writes (grep) |
| `atom.particles` | a particle datum | `ref_one` on `/atom` (the particle type is a definition datum, exempt by type) | none | rare |
| `render_target` / `render_source` | a name string another atom resolves | not a reference to the engine: a **token** (a generated unique name owned by the declaring type), or a lint finding when a literal is stored | none | unchecked today |
| `tag` and `locate(tag)` | a name string resolved to an atom | tokens (`entity_handle`) in content; `tag` does not name an entity; `locate(tag)` is linted like a stored `locate(text)` (D9) | none | unchecked today |

- **Where it is declared:** the engine (one engine file per base type, path-exempt from `stored_refs` like the other engine tables). Content never declares these ends; it writes them through `rel_add(A, nameof(A.vis_contents), X)` and the like, or a presentation helper that does.
- **Teardown:** generated, not hand-written: removing a held atom from every `vis_contents`, `client.screen` and `client.images` that names it, and clearing a client's own lists, in the destroy transaction. A `client` end is torn down on logout.
- **GC sweep pass:** after the sweep's deletes, a pass walks `vis_contents`, `client.images` and `vis_locs` of the sweep's survivors and fails on any reference to a deleted subject (BYOND does not report `vis_locs` references to the collector's finder, so the pass is explicit).
- **Cost note:** `vis_contents` and `client.images` are hot in presentation code; the declared ends use `hot = TRUE` (engine/domain only, D21) and publish nothing for presentation-only changes.

### D12. Datum-keyed assoc sets and one membership store (approved item 9)
Assoc lists keyed by datum are references the lint does not see. Verified long-lived instances: `/datum/system/atoms::after_init_pending[A] = TRUE` (`code/controllers/subsystems/atoms.dm:312`) and `batch.owner.work[kind][thing] = TRUE` (`atoms_batch.dm:174`).
- Datum-keyed assoc **sets** on long-lived vars move to the membership store (`code/controllers/kernel/membership.dm`: `member_join`, swap-remove O(1), leave on dematerialize). The lint gains assoc-key coverage (D8).
- **Merge** `kernel_membership` (`membership.dm`: members/index/sources/role/keys_of) and `lifeform_index` (`code/engine/lifeforms/registry.dm:33-44`: by_key/by_z/by_area/filed, one per registry id, plus `GLOB.radio_listen_tuned` / `radio_listen_via` at 169-170) into **one store**: one set of keys, one leave-on-delete path, one GC-sweep subject. Design of the merged keys (system type, capability type, registry id) is **(unverified)**; the constraint is no behaviour change for `members_of`, `registry_get`, `registry_all`, `REGISTRY_MEMBERS`.

### D13. One native player link (approved item 10)
Writes to a mob's `key`, `ckey` or `client`: about 104 non-test lines by a dot-write grep (`\.(key|ckey|client) =`; the task quoted 97) **(grep, approximate)**, for example `observer.key = key` (`code/modules/mob/new_player/lobby_browser.dm:189`), `replacement.key = key` (`login.dm:7`). The persistent client link exists: `persistent_client.mob` is a pair with `mob.persistent_client` written by `rel_set` (`code/modules/client/persistent_client.dm:75-83`), and `client`/`persistent_client` are plain vars with a tracked setter (`persistent_client.dm:60-72`, `code/modules/client/client procs.dm:255-259, 406`).
- One choke point `bind_player(mob, key)` does the native assignment (`mob.key =`) and updates the persistent client relation; every other `.key/.ckey/.client` write is a lint finding (`player_link`, ratchet then ban).
- Resleeving records stop holding raw `mind_ref` and `client_ref`: `infocore_records.dm:24,88-89,161-163` (mind written by `rel_set`, client written raw) become a ckey and a token. Readers: `code/modules/resleeving/computers.dm:217,228,438,507`, `machines.dm:484`, `sleevecard.dm:67-70`.

### D14. Reflective writes go through the verbs (approved item 11)
`vv_edit_var` ends in `vars_write()` (`code/datums/datumvars.dm:11-58`). `vars_write` writes `E.vars[name] = written` for any var without a stat or schema (`code/engine/stats/vars_write.dm:43-48`); its header says "any other var is refused", which the code does not do. A relation var edited this way skips the reverse index, the owner stamp and publishing. Other reflective writers: buildmode (`code/modules/admin/verbs/buildmode.dm:452,459,921`), DNA copy (`code/game/dna/dna2.dm:85-91`), NTSL (`code/modules/scripting/Interpreter/Interpreter.dm:184,193`), and the `vars[x] =` family (172 non-test grep lines, most in the engine **(approximate)**).
- `vars_write` (the one by-name writer: VV, SDQL, serializers, map loader, DNA, record copy) routes a **declared relation var** to `rel_set` / `rel_add` (single / many) and a declared owned var likewise, or refuses with a report. Buildmode, DNA and the interpreter call `vars_write` instead of `vars[x] =` (their `ALLOW(api)` keeps go). `vars_write`'s header is fixed to say what it does.
- A relation var written through the generic path is a test failure (`rel_write_undeclared` family).

### D15. Rust-held handles (approved item 13)
`/datum/gas_mixture` holds `_extools_pointer_gasmixture`, a bare slot number (`code/ATMOSPHERICS/gasmixtures/gas_mixture.dm:61`; `MixRef::Main(u32)/Pipe/Turf` has no generation, `verdigris/ffi/src/gas/mix.rs:51-58`). The slot is freed on `lifecycle_unbind` and reused by the next register; gas mixtures use `QDEL_HINT_IWILLGC` and never enter the collector's check queue (`gas_mixture.dm:~100`), so a DM reference that outlives its unbind is not caught by the GC and reads another mixture's moles.
- **Generation tokens** for the main-owned and pipe-region ids (the vg-core handle layout, 20-bit index + 4-bit generation, `verdigris/README.md:74`; the exact packing of `MixRef` ids with the pipe/turf bases is **(unverified)**): a stale handle is rejected and reported once.
- **SSvg tables:** `bound` and `entities_by_index` hold raw datum references (`code/datums/native/entities.dm:30-34`; the system type is exempt from the lint). Assert, in the GC sweep, that after the sweep's deletes neither holds a subject and that the hard-delete counter is zero for every type that binds (`atoms_movable.dm:96-107` unregisters; `bind_datum`/`unbind_datum` for non-atoms, `entities.dm:~60`). `vg_entity` already carries a generation in its high bits (`VG_ENTITY_INDEX_MASK` use at `entities.dm:~42`).

### D16. Folds into the declared forms (approved item 14)
| Site | Today | Becomes |
|---|---|---|
| mob chunk watchers | `watchers: REF(watcher) -> list(mask, handler)` and `living_refs: REF(mob) -> TRUE` (`mob_chunks.dm:18-23`) | owned watch datums (the chunk `owns_many` them) each with a `weak` watcher; living index from the merged membership store (D12) |
| tgui ui / user / src triple | `links(/datum/tgui::user, /mob::tgui_open_uis ...)`, `ref_one(src_object)`, `ref_one(window)` (`code/modules/tgui/tgui.dm:644-648`); `open_tguis` on `/datum` is an undeclared list in the baseline (`code/datums/datum.dm:29`) | **two links** (user pair, src_object pair with `open_tguis` as its many end). `transfer_ui` writes `ui.user = target` and edits both `tgui_open_uis` lists by hand (`code/controllers/subsystems/tgui.dm:691-704`, a bug against the declared link) and becomes **one `rel_set`** |
| observer events | `OBSERVER_EVENT_DESTROY` (`code/__defines/observer.dm:1`); `register` stores `listeners[procOwner] = proc_call` on a sparse atom var (`code/datums/sparse_vars/observer_events.dm:8-19`); fired from `/atom/on_destroy` (`code/controllers/observer_listener/atom/observer.dm:13-16`) | deleted. The one live user, the syndicate ID (`syndicate_ids.dm:82-90`), already has `ref_one(registered_user)` (line 26) and uses `on_unlink`; the other mention (`effect_system.dm:257`) is inside a block comment (249-263) |
| shuttles and landmarks | about 30 baseline vars (`code/modules/shuttles/*`, `overmap_shuttle.dm`, `rogueminer/*`) | declarations: pairs where both ends are vars, `ref_one`/`by =` otherwise |
| UI "selected" refs | `selected_pod/printer/sleever` (`resleeving/computers.dm`), `selected_experiment`, `selected_soul` | `weak = TRUE` (a null check at use, no reaction) |
| radio devices | `devices: list/list/obj` per `/datum/radio_frequency` (`code/game/objects/items/devices/radio/radio_service.dm:92`) | keyed `ref_many` (filter key) |
| AI pack sightings | `sightings: ref text of a mob => list(...)` (`pack.dm:33`) | keyed by token; mob members weak |
| holder back-pointers | `holder`, `holder2`, `my_atom`, `hostpda` ... | D6 |

### D17. Destroy policy and "survives container" (approved item 15)
Master today: `slot()` defaults to **SPILL** (`slot_def.dm:50,290`); `owns_one/owns_many` default to **DELETE** (`entries.dm` `on_destroy = ON_DESTROY_DELETE`), and `owns_*` has no location. `lifecycle.md` section 3 says "every slot declares one policy". The engine's own slot defs differ from the rule below: `SLOT_DROP_DELETE` on the storage slot ("contents go with it, as before", `code/library/containers/storage.dm:207-215`), folder pages (`code/modules/paperwork/folders.dm:20`), vending stock (`code/datums/containment/stock.dm:67`), the implant site (`code/modules/body/organs/organ_external.dm:134`), the part-tree slots (`code/modules/body/parts/part_slots.dm:29`), and four `slot(SLOT_HIDDEN_UPLINK, ... on_destroy = ON_DESTROY_DELETE)` sites (`code/game/objects/items/devices/uplink.dm:243,257,264`, `code/game/objects/items/weapons/implants/implantuplink.dm:8`). Six slot defs still use `SLOT_DROP_HOLDER`, which `lifecycle.md` says is removed (`stock.dm:52`, `dna_modifier.dm:95`, `mecha.dm:386`, `body/slots.dm:42,86`, `disposal_machines.dm:77`).

**The rule:**
- **SPILL is the default for anything that sits in a slot.** A bag, a locker, a folder drops what it holds when it is deleted.
- **`SPILL_FRACTION(f)` is a general slot destroy policy** (user decision, 2026-10-17): on the holder's destruction a fraction `f` (0 to 1, default **25%**, `SPILL_FRACTION_DEFAULT`) of the contents spills to the holder's location and the rest is deleted (`spent()`). The pick is random, without replacement, and rounds up so a non-empty slot with `f > 0` spills at least one. It is a slot policy like `SPILL` and `DELETE`, not vending-specific; vending stock is its first user. A `survives_container` thing always spills (below) and does not count toward the deleted share. Slot capacity and admission stay with the admission lane; only the destroy policy is declared here.
- **DELETE only for parts that are the holder's own construction** (a limb's organs and child limbs, a hidden uplink the type makes with `starts =`, a machine's own board and components). If the holder does not create it with `starts =` or by its plan, it is not its construction.
- `owns_*` (no location) keeps DELETE: it is not a slot.
- Consequence: the storage slot, folder pages and the implant site change to SPILL, and vending stock to `SPILL_FRACTION(0.25)` (a behaviour change, **flagged**). **Vending stock does not take plain SPILL: it uses `SPILL_FRACTION(0.25)`** (decided by the user: a destroyed vendor spills about a quarter of its stock and the rest is lost). `SLOT_DROP_HOLDER` is removed with its six users.
- **Lifecycle property `survives_container`** (a proc on the thing, default FALSE; TRUE for a mob with a mind or client, for a brain/MMI holding a mind, and for items like the nuke disk): phase 3 (`dq_lifecycle_resolve_slot_entry`) checks it **before** the DELETE branch (`lifecycle.dm:111-113`) and spills instead, whatever the slot's policy; the same check applies to latent entries (`lifecycle.dm:~159`) and to `consume`/cascade `spent()` calls from a container's transaction. No slot-level mob flag (`is_mind_slot` stays only for the ghost/MMI resolver of a destroyed *body*, phase 0.5).

### D18. Organs and limbs (approved item 16)
Master already has most of the shape: nested keyed slots per limb (`SLOT_ID_PART_CHILD`, `SLOT_ID_PART_ORGANS`, keyed by `organ_tag`; root on the humanoid plan), internal organs only in those slots (organ_slots lint, ceiling 0), subtree adopt and release (`code/modules/body/parts/part_slots.dm`, `attach.dm`), and a sever-and-reattach test between two humans (`code/modules/unit_tests/dq_part_lifecycle_tests.dm:51-93`). What is not declared:
- raw `mob.organs` / `organs_by_name` caches (`code/modules/mob/living/organs.dm:4-5`; `organs` has a `ref_many` only in the combat_ai file, `code/modules/combat_ai/integration/mob_living.dm:44`; `human_defines.dm:3-4` initialises them to `list()`), filled by `dq_part_cache()` (`attach.dm:170-185`);
- `organ.owner` is a stored var written by `adopt_part` with `rel_set(part, nameof(part.owner), owner)` (`attach.dm:233`); `resolve_owner()` already derives it by walking the ledger (`attach.dm:108-125`).
- **Target:** owner is derived from the slot (`owner_of` along the tree, D6) and the var is removed; the `organs`/`organs_by_name` caches become generated reads of the tree (or the one derived cache, declared); organ effects (`joined_body`, restrictions, verbs) are `while_slotted` activations scoped to the part's time in the slot (final_api section 6 "A slot entry is an activation scope"), so release revokes them by the one teardown path.
- **Replant test** (new): detach a limb with organs, put it in a bag, attach it to a second body; assert the first body released every link and stat the limb gave (no `organs` entry, no hold, no activation), the second body gained them, and bag and bodies leave no surplus reference in the GC sweep. The existing test (`dq_part_sever_and_reattach`) has no bag step and does not check stats **(read from its header comment, not run)**.
- Part slots stay `DELETE` (own construction, D17); the implant site (stuck-in items) becomes SPILL.

### D19. Latent contents (approved item 17)
`containment.md` section 4.5 says an item collapses "only when it serializes (so it holds no relationships or running behaviour)". Master is looser: collapse counts relation views naming the node as accounted for and parks them (`collapse.dm:144-150`, `views.dm:588-605`).
- **Declared relations pin an atom real**: a collapse is refused while any relation (other than its own slot edge to the holder) names it; `rel_incoming_refs` stops counting toward "accounted"; `rel_go_dormant`/`rel_wake` are removed once nothing needs them.
- **Weak refs and tokens survive** via `entity_handle_park` (`handles.dm:134-143`): they resolve null while parked and resolve again after `entity_handle_unpark`.
- **Nothing dangles into a latent entry**: no relation, link, owner stamp or native built-in entry may name a latent entry; a test collapses and re-materializes a subject with each reference kind and asserts the right outcome (refused, or survived as a token).
- Cost: fewer collapses (anything referenced stays real). The size of the loss is **(unverified)**; measure with the boot census at integration (no benches during the rewrite).

### D20. Ownership conflicts, deletes from elsewhere, GC coverage (approved item 18, corrects the first draft's D9)
- A **second owner** is already refused by `own_stamp()` (`ownership.dm:116-127`, `OWN_REPORT`): this becomes a **hard test failure** (the report is a `stack_trace`, deduplicated by message in live worlds; the test harness captures through `GLOB.dq_lifecycle_report_capture`, `lifecycle_links.dm:37-41`).
- **`qdel` of an owned value from elsewhere** keeps the doc behaviour (final_api section 6: the var clears): `own_release_from_owner()` clears (`ownership.dm:540-555`) and **adds a debug report** (a log line, not a runtime) so such deletes are findable.
- **GC sweep (D12 of the user's numbering):** every converted type joins `dq_gc_sweep_build()` (`code/modules/unit_tests/dq_gc_sweep_tests.dm:165-217`; today a representative set) and the debug hard-delete counter (`code/controllers/subsystems/garbage.dm:94-124`) is asserted zero for it. **Handle slots are counted too:** the sweep compares live slots (`length(GLOB.om_handle_slots) - length(GLOB.om_handle_free)`) before and after, because a `weak` relation leaks a slot, not an object, when its target's phase-5 release is skipped.

### D21. Tracked-ness, performance, spelling (was D8)
Reads through a relation are generated hops; accept reactive hops for content; `hot = TRUE` stays engine/domain. Plain lists over 24 members are reverse-indexed, alist sets are O(1); hot lists (`all_doors`, radio tuning, adjacency) become alist sets. Benchmarks only at integration. The sweep writes `entity_handle`/`resolve_handle`; `ref_token`/`resolve_token` is a final mechanical rename with the old names banned.

## 4. Closure argument: every storage path ends declared, linted or counted

| Path a reference can be stored by | Form it must take | Caught by |
|---|---|---|
| instance, static or global var of atom/datum type | declared relation (or `weak`) | `stored_refs` var rule; `rel_write_undeclared` for writes (D1) |
| untyped var or list assigned an atom | declared, or typed | `untyped` rule, fail closed (D8) |
| list member | `ref_many` / `owns_many` / `weak` / alist set | `stored_refs` list rule |
| assoc **key** or value | membership store, or handle keys | assoc-key coverage (D8, D12) |
| proc-static list | same as a list var | list rule (proc-static place) |
| turf / client var | handle (generation / connection generation) | NOT_REFS revisited (D8, D10) |
| `/image` with `loc`, `vis_contents`, `client.images` | engine-declared native ends (D11) | `native_ref_write` lint + sweep pass |
| REF / `\ref[` / `locate(text)` | one request only | `ref_text` lint (D9) |
| deferred call arguments | captured as handles by the engine | `ownership` lint (CALLBACK banned outside core) |
| pooled record | transient, reset on release | pool lint + structural reset check; pooled never a relation target (D7) |
| sparse slot, latent entry | not a reference target | D19 test |
| reflective write | `vars_write` to `rel_set` | D14 |
| saves | ids, ckeys, names | `saved_handle` lint (D10) |
| Rust-held ids | generation tokens | D15 test + sweep |
| membership / registry store | one store, leave on dematerialize | sweep subjects (D12, D20) |
| anything else, anywhere | -- | `dq_gc_sweep` over every converted type + hard-delete counter + handle-slot count (D20) |

The engine's own tables (relation indexes, handle slots, membership) hold references by design and are exempt by path (`lint_scopes.toml:1438-1439`); they are covered by the sweep and the counters, not the lint.

## 5. Waves

Each wave edits everything first, then one compile and one focused test batch, then `analyze baseline --update --lint stored_refs`. Site counts are from the baseline (691: var 523, list 168) and the by-name estimate in D1; the per-area split below is a grep-level estimate **(approximate)**. Baseline by area now: `code/engine/*` about 160, `code/modules/scripting` 27, `code/controllers/subsystems` 26, `code/_helpers/global_lists.dm` 22, shuttles 21, projectiles 21, antagonist 24, vore 19, tgui 19, mining 15, overmap 14, modular_computers 13, nifsoft 12, xenoarch 11, resleeving 11, pda 11, shieldgen 10, client 10.

| Wave | Content | Sites | Ban or ceiling at the end |
|---|---|---|---|
| 0 | declare the already-`rel_set` vars (D1), `weak = TRUE`, `conflict = REFUSE` on var pairs, `links()` owns-end build error (D3), `by =` pin test (D4), `survives_container` and SPILL default decisions (D17), client/turf handle generations (D10), `ref_text` / `saved_handle` / `rel_write_undeclared` / `untyped` lints with their own baselines, exact `analyze` report | -190 to -280 declared (upper bound) | **`rel_write_undeclared` hard ban (empty baseline)**; `own_entry_of_kind` stops learning |
| 1 | kernel and pooled records, framework types (D7, D8) | ~165 | ceiling 0 `code/engine/`, `code/contracts/` |
| 2 | global and per-system lists, membership merge, datum-keyed sets (D12) | ~80 | ceiling 0 `code/_helpers`, `_global_vars`, `controllers`; assoc-key rule on |
| 3 | owner back-refs and machine links: reagents, power, shuttles, shieldgen, mining, overmap, modular computers (D3, D6, D16) | ~160 | ceiling 0 per dir; `paired_vars` hard ban |
| 4 | targets and mob/item: projectiles, antagonist, vore, nifsoft, pda, xenoarch, tgui, resleeving; folds (D13, D16: mob_chunk, tgui, radio, packs, observer events deleted) | ~170 | ceiling 0 for those dirs; `OBSERVER_EVENT_*` deleted (hard ban); `player_link` ratchet |
| 5 | client/session, `bind_player`, reflective writes, scripting (D13, D14); the 97 to 104 `key/ckey/client` writes | ~60 | `player_link` hard ban; `ALLOW(api)` `vars[...]` keeps in content gone |
| 6 | native built-in ends (D11), organs/limbs (D18), latents (D19), Rust handle generations (D15), destroy-policy flips and `SPILL_FRACTION` (D17) | n/a (new rules) | `native_ref_write` ratchet then ban; `SLOT_DROP_HOLDER` removed (hard ban); replant test and sweep extended |
| 7 | baseline empty: `stored_refs` becomes a hard ban; `ref_token`/`resolve_token` rename (mechanical) | rest | no baseline file; old handle names banned; `ref_text` hard ban |

After wave 0, waves 1 to 5 can run in parallel by directory; wave 6 items are independent of each other. A file moves into the new tree only when fully migrated (AGENTS.md section 3c).

## 6. Risks

1. **Behaviour change on delete.** `OTHER_CLEAR` now nulls vars old code left stale. Mitigation: per-type delete tests in the sweep, `on_unlink` where old code did work.
2. **Destroy-policy flips (D17).** Storage, folders and implants now spill; vending spills a quarter (`SPILL_FRACTION`), decided by the user. The remaining per-site flips are reviewed in wave 6.
3. **Latent savings fall (D19).** Anything referenced stays real. Unmeasured.
4. **`weak` readers are not reactive.** A reader that needs the target's death uses a normal relation; wrongly choosing `weak` loses a reaction. The per-site test in D5 is the guard.
5. **Client handle generation (D10)** changes who a stored client handle resolves to after a reconnect; every current user of `"@ckey"` handles must be listed first **(unverified: not enumerated)**.
6. **`links()` owns-end** has no site yet (D3); building support for a site that may not exist is avoided on purpose.
7. **Init order** for `by =` and links at map load: pin before converting map-placed machines.
8. **New lints seed baselines** whose size is unknown until wave 0's report; they could be large. Fail-closed untyped coverage is the most likely to be.
9. **Counts are approximate**; the exact report sizes the waves.

## 7. Decisions on the open points (user, 2026-10-17)
- Visual references have no special kind: BYOND built-ins become engine-declared ends of the existing kinds with native storage (D11). The names `vis_one` / `vis_many` and `visual()` are not used.
- Vending stock uses `SPILL_FRACTION(0.25)`, a general slot destroy policy (D17).
- `owner_of` is for non-hot code; hot paths keep a `ref_one` back-reference (D6).
- **REFUSE on a var pair reports on the plain path** (decided 2026-10-17, implementation lane): `rel_set` / `rel_add` refused by `links(conflict = REFUSE)` return null and report (`OWN_REPORT`, a test failure), as D3 says. A caller for which a refusal is an expected answer says so with `rel_try_set` / `rel_try_add` (`code/engine/refs/views.dm`), which return null silently. A silent null on the plain verb would hide bugs. The sparse `link_make()` keeps its FALSE return (its callers already test it).
- **Pooled records' fields are transient by structure** (decided 2026-10-17): the `stored_refs` lint does not count a field of a `/datum/pooled` subtype (`pooled_holder()` in `tools/analyze/src/lints/stored_refs.rs`), because release resets every field to a fresh instance's value (`pool_reset_plan()` is built from the instance's own vars, so a new field is covered with no declaration). `relations_pooled_release_resets_every_field` checks the same root (`subtypesof(/datum/pooled)`), so the rule and its proof cannot drift. Not a hand list; the old `POOL_DECLARE` form is not covered. D7's "pooled is never a relation target" stands.

## 8. Comparison with the original design

Sources compared: `proposals/reference_storage.md` (RS), `lifecycle.md` (LC), `final_api.html` section 6 (API6), and `containment.md` section 4 (CT4).

### Kept
- The two-kind rule and "everywhere a reference can be stored" list (RS, API6), the stored_refs lint shape, the shrink-only baselines, the GC sweep and its exact-count controls, the relation shapes and handle costs (RS).
- Destroy phases and the guard (LC section 2), children before parents, no nullspace parking.
- Relation kinds and write verbs (API6) unchanged in meaning; `links()` sparse form and `by =`.

### Changed
| Item | Original | Now | Why |
|---|---|---|---|
| Weak ref | hand-stored handle in a var; "no third kind" | relation option `weak = TRUE`, accessor generated | hand handles hid from the lint and each had its own accessor; D5 |
| Tokens | `ref_token` for any naming in data and for stored weak refs | tokens only in data; stored weak refs are relations | one meaning per form |
| "Not references, so free: turfs and areas, values like /image" (RS, API6) | free | turf and client are handles (z recycle and reconnect change identity); `/image` with `loc`, `vis_contents`, `client.images` are references | master's `NOT_REFS` hid real pins (`stored_refs.rs:74`) |
| Client handle | `"@ckey"` resolves to the current client | resolves null after disconnect, never to the reconnected client | `handles.dm:55-58, 202-203` |
| Pooled record (RS: "holds its entities for one delivery, reset on release") | exempt | never a relation target; structural reset check | LC section 4.1 text is stale (`POOL_DECLARE`); the live form is `/datum/pooled` |
| Slot destroy policy (LC section 3: every slot declares one policy) | mandatory declaration | SPILL default; DELETE only for own construction; `survives_container` | master's `slot()` already defaults to SPILL (`slot_def.dm:50`) but engine slot defs delete contents; mind-slot resolver is a no-op today (`lifecycle.dm:14-16`) |
| Latent contents (CT4.5: collapse only items that "hold no relationships") | master parks relations | relations pin real; only weak refs survive | restore CT4.5, avoid dormant-view machinery |
| Second owner / delete from elsewhere (API6 table) | stated | second owner a hard test failure; delete from elsewhere clears and reports | first draft's D9 wrongly implied a second owner was permitted; `ownership.dm:116-127` refuses it |
| Reflective writes | `vars_write` "refuses any other var" (its header) | routes relation vars to `rel_set` or refuses | the code writes raw (`vars_write.dm:43-48`) |
| Stored text keys | `own_key` and REF used freely in engine and content | content: handle only; REF text one request only | five naming schemes today (D9) |
| Datum-keyed assoc sets, `kernel_membership` vs `lifeform_index` | two stores; assoc keys unlinted | one store; assoc-key lint | `atoms.dm:312`, `atoms_batch.dm:174`, `registry.dm:33` |
| Organs (API6 "Containment and slots", LC section 7) | slots + caches | owner derived, caches derived, effects while-slotted | `attach.dm:233`, `organs.dm:4-5` |

### Added
`weak = TRUE`; `conflict = REFUSE` on var pairs; `rel_write_undeclared`, `ref_text`, `saved_handle`, `untyped`, `player_link` lints; engine-declared relation ends over BYOND built-ins (D11) and a native-ref sweep pass; `SPILL_FRACTION(f)` slot policy; `native_ref_write` lint; `survives_container`; `bind_player`; Rust generation tokens for gas handles; observer-event deletion; handle-slot counting in the sweep; a replant test; `links()` owns-end build error.

### Dropped
- The first draft's `by =` as an unproven "the doc says so" (now a wave 0 pin).
- RS's mention of legacy `owns()` / `rel_one()` / `rel_many()` / `OWN`/`REL` as still-declaring forms (banned: `lint_scopes.toml:1090-1095, 724+`).
- `rel_go_dormant`/`rel_wake` for relations (D19) once nothing needs them.
- `SLOT_DROP_HOLDER` (LC already says removed; six users remain).
- OBSERVER events; hand-stored handles in vars; stored REF text in content.
- RS waves 2 to 5 (replaced by section 5).

## 9. Edits `final_api.html` needs (not made here)
1. Section 6 relations table: add `weak = TRUE` to `ref_one/ref_many` (accessor generated, no index, no publish, `on_unlink` an error); add the native built-ins inventory (D11) with no new kind; allow `conflict = REFUSE` on a var pair and state that a `links()` end cannot be an `owns_*` var.
2. "Naming an entity in data": tokens only in data; a var holding an entity is a relation (possibly `weak`); stored `REF()`/`locate` text banned; `own_key`, `adj_handle`, `vg_entity` engine-only.
3. "Storing references": "no third kind" reworded (two kinds, weak is an option); "Not references" list: remove turfs/areas "never deleted" caveat for turfs (z recycle) and add clients, `/image` with `loc`, and the built-ins of D11 (declared by the engine, not content); add pooled-never-a-target; add assoc keys; "Checked" lists the new lints and the sweep extensions.
4. "Owned or contained": state SPILL default for slots, `SPILL_FRACTION(f)`, DELETE for own construction, `survives_container`; fix `slot(... on_destroy = ...)` to say the default; keep `owns_*` DELETE default.
5. Reads table: `owner_of` cost note and "hot paths use `ref_one`".
6. "Containment and slots": organ owner derived from the slot; organ effects as `while_slotted`; relations pin latent entries.
7. Section 17 (old to new): rows for hand handles, REF/locate text, observer events, datum-keyed assoc sets, raw `.key/.ckey/.client` writes, raw `vars[x] =` on relation vars.
8. Section 19 (migration): the waves of section 5; section 21: the decisions D3, D5, D10, D17, D19, D20.
9. Outside `final_api.html`: AGENTS.md section 3a "Links and ownership" row (still says new / OWN-REL) and section 3b legacy list; `lifecycle.md` sections 3, 4, 4.1 (OWN/REL, `POOL_DECLARE`) and 9 (`rel_one`); `containment.md` 4.5 stays and gains the master behaviour note; `reference_storage.md` "What to write" table and its Waves.
