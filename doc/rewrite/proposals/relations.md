# Proposal: finishing the relations layer and the `stored_refs` migration (design only)

Status: proposal, awaiting decisions D1 to D8. Scope: doc section 6 (`final_api.html`: "Relations", "Storing references", "Naming an entity in data"),
section 17 (old forms), section 19 (migration), `proposals/reference_storage.md`, and the 691 sites in `tools/ci/stored_refs_baseline.txt`.

## 0. Summary

1. **The relation layer is not what blocks the 691 sites; it is mostly on master.** `ref_one`, `ref_many`, `owns_one`, `owns_many`, `links()`
   (paired, sparse, `hot`) and `slot()` are declared in `code/engine/declare/entries.dm`; `rel_add`, `rel_remove`, `rel_take`, `rel_move`,
   `rel_private` and `rel_set` are in `code/engine/declare/relations.dm`; the alist set/map shapes, `entity_handle`/`resolve_handle` and the
   destroy transaction are in place. Usage: about 3,270 `owns_*`, 2,790 `ref_*` and 160 `links(` lines in `code/`. The legacy `OWN`/`REL` macros,
   `own_set`, `own_add`, `own_put`, `om_link`, the `ownership()` table proc and `rel_one`/`rel_many` are already hard-banned
   (`[lint.legacy_forms.lists]`), so no OWN/REL conversion is left to do (AGENTS.md section 3a's "relations: new" row is stale).
2. **What remains is a content sweep plus a few small engine gaps** (D3, D5, D6, D7). The sweep is judgement per site (relation, weak ref, or
   not a reference at all?), which is why it has stalled: the baseline records the lint's verdict, not the right declaration.
3. **About a third of the baseline is the framework's own state** (engine 144 sites, `code/_helpers/global_lists.dm` 22, scripting 49, system
   and controller lists). That needs a policy (exempt by role, or convert), not ~250 relation declarations (D6).
4. Doc section 6 spells weak refs `ref_token`/`resolve_token`; master has `entity_handle`/`resolve_handle` (text). The sweep writes the master
   names; the rename is a later mechanical step (D8).

## 1. Census (baseline at `cee490f697`)

691 sites: **var 523, list 168** (seeded 1,768 on 2026-10-12). Category shares below are a hand classification of the baseline's var names
and declaring types, approximate (+/- 10%). Wave 0 should replace them with an exact `analyze` report.

| Area | Sites | Notes |
|---|---|---|
| `code/engine/*` (declare 41, parts 25, lifeforms 20, kernel 19, change 15, ...) | 144 | definition registries, compiled tables, act/op/context records, inbox, activation |
| `code/_helpers/global_lists.dm` 22, `_global_vars`, `controllers/subsystems` 26 | ~80 | global registries of live objects, per-system lists |
| `code/modules/scripting` (NTSL interpreter) | 49 | AST nodes, parser state, interpreter scope |
| `code/contracts/acts` | 16 | `/datum/act/*` fields (actor, over, answer) |
| game and modules content (shuttles 21, projectiles 21, antagonist 24, vore 19, tgui 18, mining 15, overmap 27, modular_computers 13, nifsoft 12, xenoarch 11, resleeving 11, pda 11, shieldgen 10, client 17, ...) | ~370 | the real conversion work |

### 1.1 By pattern

| Pattern | Share | Typical sites | Target |
|---|---|---|---|
| Owner / parent back-ref (`owner`, `master`, `holder`, `parent`, `my_atom`, `hung_from`) | ~75 (11%) | `/datum/reagents::my_atom`, `/datum/disposal_system_connection::owner`, `/datum/request::owner`, `/obj/item/shield_projector/line/exosuit::my_mecha` | `links()` with the owner's `owns_*`; where the owner is a session or system, `ref_one` |
| Machine to machine links (`linked`, `circ1`, `gen_primary`, `sensors`, `apc`, `output`) | ~85 (12%) | `/obj/machinery/computer/ship::linked`, `/obj/machinery/power/generator::circ1`, `/obj/machinery/shieldwall::gen_primary`, mineral processing `output` | `links(A::a, B::b)` where both ends are vars; `ref_one` where only one end names the other; `by =` where an id already exists |
| Targets (`target`, `victim`, `autofire_target`, `current_mr`, `selected_experiment`, `original`) | ~50 (7%) | `/mob/living::autofire_target`, `/obj/item/projectile::original`, `/datum/event::victim`, `/obj/structure/portal_target::target` | `ref_one` (clears on delete); a one-shot target of a deferred call is a handle |
| Mob and item / container (`tank`, `ai_slot`, `stored_organic`, `tf_mob_holder`, `wearer`, `occupant`) | ~50 (7%) | `/obj/item/gun/launcher/pneumatic::tank`, `/obj/item/modular_computer::ai_slot`, `/obj/item/disk/nifsoft::stored_organic`, `/datum/notice/shoes_step::wearer` | `slot()` when it sits inside the holder, `owns_one` for a location-less owned value, `ref_one` otherwise; pooled notices are reset on release (D5) |
| Weak-ref candidates (previous, last-seen, remote peer, result, answer, token_ref) | ~60 (9%) | `/datum/materialize_batch::previous`, `/datum/pending_op::result`, `/datum/computer_file/program/nttransfer::remote`, `/datum/scriptError/BadToken::token_ref` | `entity_handle(x)` stored, `resolve_handle()` at use (D4) |
| Lists of refs (all 168 list sites) | 24% | `/area::all_doors`, `/obj/item/radio::secure_radio_connections`, `/datum/locations::children`, `/datum/admins::ranks`, `adjacency_members`, `radio_listen_tuned`, `/datum/act/op::reservations`, `/datum/state_context::pending` | `ref_many`/`owns_many` (alist set when order is irrelevant); a global list of live objects is `membership()`/`members_of`; a per-system list is a `ref_many` on the system |
| Registry / compiled-table state (definitions, activations, `compiled_*`, `rx_state`) | ~140 (20%) | `/datum/definition_registry::relations`, `/datum/rx_state::activations`, `/datum/scheduled_behaviour::compiled_requires` | Not content relations: they hold flyweights or procs. Fix the classifier or exempt by type (D6) |
| Client / session | ~20 | `/client::holder`, `/client::session` | `client_session` owned relations (wave 5) |
| Scripting interpreter | 49 | AST nodes, scope | one run's scratch: exempt or own under the program (D6) |
| Other | ~35 | | per site |

(Rows overlap: the list sites are also counted in their pattern's area.)

## 2. What exists today

| Form | State | Notes |
|---|---|---|
| `ref_one` / `ref_many(nameof(v), type, on_other_deleted, on_unlink, by, key)` | on master | `OTHER_CLEAR` default; `DELETE_ME` supported |
| `owns_one` / `owns_many(nameof(v), type, starts, on_destroy, copy_on_write)` | on master | `ON_DESTROY_DELETE` default; SPILL, PRIVATE_COPY |
| `links(a_end, b_end, hot, a_many, b_many, key, ...)` | on master | paired, sparse (`LINK_END`), `hot` |
| `slot(id, accepts, capacity, exposure, at, on_destroy, starts)` | on master | containment |
| `rel_set` / `add` / `remove` / `take` / `move` / `private` / `clear` | on master | type-checked, publish both ends, alist set and keyed-map shapes |
| `entity_handle` / `resolve_handle` | on master | text handles; `ref_token`/`resolve_token` (the doc's final spelling) is not on master |
| `OWN`/`REL`/`PROTO` macros, `own_set`, `own_add`, `own_put`, `om_link`, `ownership()`, `rel_one`/`rel_many` | hard-banned | engine accessors `_own_*` are private to `code/engine` |
| `stored_refs` lint | on, baseline 691 | var and list rules; exempt by path and type; no `ALLOW(stored_refs)` |
| `dq_gc_sweep` | on | zero surplus references for a representative set |

So "OWN/REL and `own_set`/`rel_set`" today means: the old macros and writers are gone from content, `rel_set` is the single write verb for a
`ref_one`, `owns_one` or single link end, and the destroy transaction does the clearing the old `Destroy()` bodies did by hand.

## 3. Decisions

### D1. Lifecycle on destroy for a swept var
- (a) default `ref_one` (`OTHER_CLEAR`); `DELETE_ME` only where the holder is meaningless without its target.
- (b) decide per site.
- (c) default `owns_one` for anything the holder created.

**Recommend (a), with `owns_one` only when the holder creates the value and nothing else keeps it (a program's state, a bomb's timer), and `DELETE_ME` on a short
list reviewed per wave.** Sites whose old `Destroy()` or target-death code did work get `on_unlink = PROC_REF(x)`.

### D2. Cardinality and inverse maintenance
- (a) every pair whose ends both exist as vars is `links(A::a, B::b)`: one write maintains both ends and replacing a single end unlinks the old partner on both sides.
- (b) declare one end (`ref_one`), look the inverse up when needed.
- (c) keep today's hand-maintained inverse vars.

**Recommend (a) when both vars exist (about 160 sites), (b) when only one end exists and nobody reads the inverse.** Cardinality comes from var types (a `list` var is the many
end). Two vars naming each other with no `links` is converted in the same commit and a `paired_vars` lint then rejects new ones. Never keep a duplicate cache var to dodge the
lint (no-workaround-state rule). (c) is rejected: it is the leak source.

### D3. Keyed and sparse relations
- (a) `by = nameof(id_var)` for id-named targets (power network id, shuttle tag, tag-linked machines), `sparse = TRUE` links for base-type pairs.
- (b) store an id and `locate()`.

**Recommend (a).** First commit of wave 0 pins `by =` with a test that it re-links on materialize, on id write and on target delete (the doc says it does; the repo should prove it
before the first use). A site that finds a target by `tag` in init becomes `by =`.

### D4. Weak ref versus relation
- (a) handle when the holder only needs the target if it still exists (history, last, peer, previous, remote, answer, result); relation when the holder must be told.
- (b) always a relation.

**Recommend (a).** Test per site: if the old code nulled it on target death (a `Destroy()` clear, or a stale-ref null check that gates behaviour), it is a relation (the clear is the
contract); if it only null-checks at use, it is a handle. No third storage kind (doc section 6).

### D5. Pooled records and contexts (`/datum/act/*`, notices, pending ops, requests: about 45 sites)
- (a) exempt by type in `[lint.stored_refs.lists]` (like `/datum/own_entry`) because they are reset on release.
- (b) kernel relations: weak while waiting, strong from the reservation (doc "Do is a commit").
- (c) hold handles.

**Recommend (b) for `pending_op`, `act` and `request` (the doc already specifies it, and the `ending_causes` leak was this shape), (a) for pooled `notice`s, each proven by a test that
releases the record and re-runs the sweep.** (c) is rejected: the snapshot fields (`A.target_name`) already serve display reads.

### D6. Framework state in the baseline (engine 144, global lists, interpreter)
- (a) fix the classifier and exempt reviewed types: a var typed as a flyweight, registry or `/datum/*_def` is not an "atom or datum"; add reviewed types to `exempt_types`.
- (b) convert everything to relations.
- (c) leave it in the baseline.

**Recommend (a) for definition and compiled-table types (~140 sites; never qdel'd), (b) for run-state holders (`act`, `request`, `pending_op`, `input_event`, live `activation`),
and for the interpreter: own the AST under the program with `owns_one` if the program is deleted by an owner, else exempt the directory by path.** (c) is rejected: the baseline
would never reach zero and the ratchet could not become a hard ban. No `ALLOW(stored_refs)` in any case.

### D7. Save and serialization
- (a) relations are runtime-only; saves store ids or names; on load a relation re-links by `by =` or by a lookup.
- (b) serialize relation edges.

**Recommend (a).** Types that are both saved and related (`stored_organic`, `current_mr`, resleeving `mylandmark`) save their id in the record and read it back through `by =`. A
saved handle is a bug (handles are per round and generation-checked): add a `saved_handle` lint flagging an `entity_handle()` result written to a saved var. Tokens
(`ref_token`) get the same rule when they land.

### D8. Tracked-ness, reads, performance and spelling
- Tracked-ness: a relation var is a tracked source; reads through it become generated hops. Options: (a) accept reactive hops everywhere; (b) `hot = TRUE` pairs; (c) pre-resolve in callers.
  **Recommend (a) for content; `hot = TRUE` stays engine and domain only (existing lint).**
- Perf: reverse-indexed lists over 24 members, alist sets are O(1); handles cost about 1.6 us (repeat) and 4 us to resolve, so resolve once per proc, never per tick per member.
  Large per-tick lists (`all_doors`, radio tuning, adjacency) become alist sets. Benchmarks run only at integration (no benches during the rewrite), with one row each for lighting,
  projectiles in flight and powernet members.
- Spelling: the sweep writes `entity_handle`/`resolve_handle`; `ref_token`/`resolve_token` is a final mechanical rename with the old names banned.

**Recommend as stated.**

## 4. Conversion waves

Each wave edits everything first, then one compile and one focused test batch, then `analyze baseline --update --lint stored_refs`; the GC sweep is extended with the wave's types.

| Wave | Content | Est. sites | Lints / bans at the end |
|---|---|---|---|
| 0 | `by =` pin test (D3), classifier and reviewed `exempt_types` (D6), `saved_handle` lint (D7), exact category report | -140 to -190 | scope entries only; no new ALLOW |
| 1 | Kernel and pooled records: `pending_op`, `act`, `request`, `input_event`, `activation` (D5) | ~45 | stored_refs ceiling 0 for `code/engine/`, `code/contracts/` |
| 2 | Global and per-system lists (`global_lists.dm`, systems, controllers): `membership()` or `ref_many` on the system | ~80 | ceiling 0 for `code/_helpers`, `_global_vars`, `controllers` |
| 3 | Owner back-refs and machine links via `links()`: reagents, power, shuttles, shieldgen, mining, overmap, modular computers | ~160 | ceiling 0 per converted dir; `paired_vars` lint hard ban |
| 4 | Targets and mob/item: projectiles, antagonist, vore, nifsoft, resleeving, pda, xenoarch, tgui | ~170 | ceiling 0 for those dirs |
| 5 | `/client` state onto `client_session`; scripting (D6 outcome); stragglers | ~40 | baseline empty; `stored_refs` becomes a hard ban (no baseline file) |
| 6 | `ref_token`/`resolve_token` rename | mechanical | old names hard-banned |

After wave 0, waves 1 to 5 can run in parallel by directory. A file moves into the new tree only when fully migrated (AGENTS.md section 3c).

## 5. Risks

1. **Behaviour change on delete.** Old code that never cleared a var kept a stale ref; `OTHER_CLEAR` now nulls it, and code that read a deleted object's vars changes outcome.
   Mitigation: per-type delete tests in the GC sweep, `on_unlink` where the old code did work.
2. **Init order.** A `by =` or `links` target not yet materialized at map load reads null until it is. Pin the order (wave 0) before converting map-placed machines (wave 3).
3. **Reactive hops in hot loops** (D8): measured at integration only.
4. **Double declaration.** A var declared on both a type and its parent errors at build; the sweep greps the parent chain first.
5. **Tests that raw-set relation vars** use `TEST_RAW_SET`; a conversion that breaks a test is a fixture fix, never a baseline add.
6. **Counts are approximate.** The pattern split is hand classified; wave 0's exact report sizes the waves.
7. **Saved handles** (D7) die with the round and with recycled refs.
