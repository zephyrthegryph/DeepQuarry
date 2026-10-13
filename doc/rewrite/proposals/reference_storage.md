# Reference storage: relations or weak refs, nothing else (approved 2026-10-12)

A deleted object is collected only when nothing references it. A reference that nothing clears keeps the
object alive past `qdel()`; the collector fails its check five minutes later and hard-deletes it, a
full-world reference walk (150 ms and up on the live server). Every hard delete on the live server is one
such reference.

## The rule

Every stored reference to an atom or datum is one of two kinds:

| Kind | Forms | On delete |
|---|---|---|
| Declared relation | `owns_one`, `owns_many`, `ref_one`, `ref_many`, `links()`, `slot()` in the type's `CAPABILITIES` block (the legacy `owns()` / `rel_one()` / `rel_many()` tables and `OWN`/`REL` lines still declare them on master) | the destroy transaction clears both ends; owned values are disposed of by `on_destroy` |
| Weak ref | `entity_handle(x)` read back with `resolve_handle(h)` (the final spelling is `ref_token` / `resolve_token`, final_api.html section 6) | nothing to clear: the handle stops resolving |

"Stored" covers every place a value outlives the proc that put it there:

- a var (instance, `static`, `global`, `GLOBAL_*`);
- a list's members, assoc keys and assoc values, on a var or in a proc's `var/static/list`;
- a sparse slot;
- a deferred call's arguments: `after()`, `every()`, request and job payloads already capture every datum
  argument as a handle (`capture_args()`, `code/engine/time/handles.dm`); `CALLBACK` is banned outside the
  core (the `ownership` lint);
- caches, pools, queues, indexes: key by a handle, an id or a type, hold handles.

Not references, so free: locals and local lists (scratch for one call); turfs and areas (never deleted);
registry and flyweight instances, kernel systems and controllers (never `qdel()`ed); values (`/image`,
`/mutable_appearance`, `/icon`, `/matrix`, `/regex`). A pooled record (a notice, a context) holds its
entities for one delivery and is reset on release.

### What to write

| Today | Write |
|---|---|
| `var/obj/item/cell/cell` set by hand, cleared in `on_destroy()` | `owns_one(nameof(cell), /obj/item/cell)` (or `slot()` when it sits inside the holder) |
| `var/mob/user` pointing at something it does not own | `ref_one(nameof(user), on_unlink = ...)` |
| two vars that name each other | `links(/A::a, /B::b)` |
| `var/list/members` filled with `+= x` | `ref_many(nameof(members), /type)` (or `owns_many`) and `rel_add()` / `rel_remove()` |
| a global or system list of live objects | a `membership()` registry, or a `ref_many` on the system |
| a cache keyed by an object | key by `entity_handle(x)` (or the object's id), store handles |
| a waiter or deferred record holding its target | `entity_handle(target)`; `resolve_handle()` at fire time, drop the record when it is null |
| a reference that must survive only one call (`ending_causes`) | drop it in the same call that set it, whatever path the call took |

## The lint

`stored_refs` (`tools/analyze/src/lints/stored_refs.rs`, scopes in `tools/ci/lint_scopes.toml`) reads the
typed model (the full dreammaker parse):

- `var`: a var whose declared type is an atom or datum (not a turf, an area, a client, a registry,
  flyweight, system or controller type) that no relation declares, reported at the declaration;
- `list`: a list var, global or proc-static list that some proc fills with a value whose static type is an
  atom or datum (`L += x`, `L |= x`, `L[k] = x`, `L[x] = v`, `L.Add(x)`, `L.Insert(i, x)`, `L = list(x)`,
  and the LAZY* macros, which the parser expands), unless a many relation declares it. The static type is
  what the model can say: `src`, `usr`, a parameter, a local, a var reached by `a.b`, `new /type`, a typed
  list's element, a proc declared `as /type`. A value from an untyped call is not seen: the lint
  under-counts, it never guesses.

The reference machinery itself (relation tables, handles, the lifecycle transaction, the collector) and
tests are exempt by path. The baseline (`tools/ci/stored_refs_baseline.txt`) is shrink-only:
`analyze baseline --update --lint stored_refs` after each wave. No new `ALLOW(stored_refs)`.

Seeded 2026-10-12: 1,768 sites (var 1,391, list 377); 1,737 after generated output was exempted (var 1,374, list 363).

## The GC sweep test

`/datum/unit_test/dq_gc_sweep` (normal tier, `code/modules/unit_tests/dq_gc_sweep_tests.dm`) creates and
deletes a representative set (machines, items, a human with an outfit, simple mobs, a window datum opened
and closed, HUD screens, lights) and checks each deleted object's reference count right after its delete,
against a control datum measured the same way. A surplus reference fails the test and runs the reference
finder on that object, so the log names the holder. No waiting for the collector's five-minute check.

## Waves

1. **Live hard deletes** (this lane's first slice). The live server's `PERF_PROFILE` garbage section
   (2026-10-12) named two types:
   - `/atom/movable/screen` [0x2000007], every round about five minutes after boot. The reference finder
     (unit-test logs) found it in the global `ending_causes` list: a caused ending whose `qdel()` never
     reached `ending_begin()` left its entry, which held the thing and its `by` (the screen) for the rest
     of the round. Fix: `ending_qdel()` records the cause, deletes, and drops the entry in the same call
     unless a collecting scope deferred the delete; every engine verb goes through it.
   - `/datum/tgui` (and its `/datum/tgui_window`): `close()` skipped `SStgui.on_close()` when the UI's
     window relation had already been cleared (a deleted window), so the spent UI stayed in `all_uis`,
     `autoupdating` and its object's `open_tguis`. Fix: the deregistration runs on every close. The client
     session's asset waiters held their target strongly; they hold a handle now.
2. Caches, pools and queues (the `list` rule's proc-static and global lists).
3. Deferred-call payloads and waiters that still hold objects.
4. Legacy instance lists (`var/list/x` of live objects) to `ref_many` / `owns_many`.
5. Object vars to `ref_one` / `owns_one` / `links()`, worst types first.

Each wave lowers the baseline and lands on its own.

## Relation shapes and what they cost (2026-10-13)

The wave conversions kept hitting hot engine tables the relation core was too slow or too narrow for. The core now has these shapes
(`code/engine/refs/members.dm`; `rel_add`, `rel_remove`, `rel_clear`, `rel_take` work on all of them):

| Shape | Declare | Membership | Add | Remove one | Order | Keys |
|---|---|---|---|---|---|---|
| plain list | `var/list/x` + `ref_many` / `owns_many` | reverse index (a list over 24 long is not scanned) | O(1) | scan at the engine's list speed (the front is O(1): a queue) | insertion order | text, in an owns_many |
| alist set | `var/alist/x = alist()` + `ref_many` / `owns_many` | `member in x`, O(1) | O(1) | O(1) | the hash's, not insertion | none |
| alist map | `var/alist/x = alist()` + `ref_many` / `owns_many`; `rel_add(E, var, member, key)` | `rel_keys_of()` | O(1) | O(keys of the member) | the hash's | number, text or path; a member may sit under several keys |

- `islist()` is FALSE for an alist. Relation code asks `REL_LISTLIKE(x)`; your own code that reads a relation var does `istype(x, /alist)` where
  it matters. `for(var/m in set)` walks the members; `for(var/k, m in map)` walks key and member.
- A number is an index in a plain list, never a key, so a numeric key makes an alist (a null var is made one by the first `rel_add(..., key)`;
  declare it `= alist()` so readers see one before the first write). A sparse or fixed-size table (a meter's slot table, regions by id) is an alist
  map with numeric keys: reading is `x[key]`, and an empty slot is an absent key.
- `rel_add(E, var, null, key)` empties that key. Replacing the member under a key disposes of the old one (owns_many) unless it still sits
  under another key. Deleting a member, `rel_remove`, `rel_take(member =)` and `rel_clear` take it from every key it sat under: the holder keeps
  each member's keys (`rel_keys_of()`), so none of these scans the map.
- Keep an ordered `list` only where a reader needs the order (a FIFO queue, a sorted display). Everything else that is a set or a table should be
  an alist.
- An alist is not walked by the reference finder (`find_references`), so a leaked member of one is harder to find: the GC sweep test is the check.

Handles (`entity_handle` / `resolve_handle` / `entity_handle_of`, `code/engine/time/handles.dm`) stay text, because a handle keys plain lists
everywhere. What changed is where the text work is done: once, when a slot is taken.

| Operation | Before | After |
|---|---|---|
| `entity_handle(D)`, first call | 31.6 us | 16.6 us (9 us once `D` has its relation key) |
| `entity_handle(D)`, repeat | 3.3 us | 1.6 us |
| `resolve_handle(h)` | 31.4 us | 4.0 us |
| `entity_handle(turf)` | 165 us | 2.9 us |
| `resolve_handle(turf handle)` | 5 us | 6 us the first time (parsed), about 2 us after (the position is cached as a number) |

A turf handle is the turf's key (no new string) once the level has been released and reused it carries `#<generation>`; a handle to a
deleted datum stays dead when its slot is reused (the slot's text carries the generation, and a freed slot's text leaves the index).

The cost passes are `dq_rel_perf_*` (`code/modules/unit_tests/dq_rel_perf_*.dm`): microseconds per operation at two sizes, no thresholds.
`dq_rel_core_*` is the correctness set: long lists, sets, numeric tables, deletion of members and holders, handle reuse.
